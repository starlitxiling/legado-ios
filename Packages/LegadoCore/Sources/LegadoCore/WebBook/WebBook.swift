import Foundation

public enum WebBookError: Error, Equatable {
    case missingRule(String)
    case emptyToc
    case emptyContent
    case emptyDownloadURLs
    case httpStatus(Int, String)
    case unsupported(String)
}

public final class WebBook {
    public let source: BookSource
    private let client: any HttpClient
    private let processor: ContentProcessor
    private let now: () -> Int64
    private let cookies: CookieStore
    private let precisionSearch: Bool
    private let tocCountWords: Bool
    private let jsSourceApi = JsSourceApi()

    private var isJsSource: Bool {
        !(source.mainJs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func jsSourceEngine() throws -> JsSourceEngine {
        try JsSourceEngine(source: source, client: client, cookies: cookies, api: jsSourceApi)
    }

    public convenience init(source: BookSource, client: any HttpClient, replaceRules: [ReplaceRule] = [],
                            precisionSearch: Bool = false, tocCountWords: Bool = false,
                            now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.init(source: source, client: client, replaceRules: replaceRules, precisionSearch: precisionSearch,
                  tocCountWords: tocCountWords, cookies: CookieStore(), now: now)
    }

    public init(source: BookSource, client: any HttpClient, replaceRules: [ReplaceRule] = [],
                precisionSearch: Bool = false, tocCountWords: Bool = false, cookies: CookieStore,
                now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.source = source
        self.client = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
        self.processor = ContentProcessor(rules: replaceRules)
        self.now = now
        self.precisionSearch = precisionSearch
        self.tocCountWords = tocCountWords
        self.cookies = cookies
    }

    public func checkKeyword(default fallback: String) -> String {
        guard let value = source.ruleSearch?.checkKeyWord,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !["http", "::", "++", "--"].contains(where: value.contains) else { return fallback }
        return value
    }

    public func search(key: String, page: Int = 1,
                       filter: BookList.Filter? = nil) async throws -> [SearchBook] {
        if isJsSource {
            return try jsSourceEngine().search(key: key, page: page).filter {
                (!precisionSearch || ($0.name ?? "").contains(key) || ($0.author ?? "").contains(key) || $0.kind?.contains(key) == true)
                    && (filter?($0.name ?? "", $0.author ?? "", $0.kind) ?? true)
            }
        }
        guard let url = source.searchUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebBookError.missingRule("searchUrl")
        }
        let context = WebBookContext(source: source, client: client, cookies: cookies)
        let response = try await context.request(url, baseURL: source.bookSourceUrl ?? "",
                                                 bindings: ["key": key, "page": page])
        return try await BookList.analyze(context: context, body: response.body, baseURL: response.url,
            isSearch: true, filter: { name, author, kind in
                (!self.precisionSearch || name.contains(key) || author.contains(key) || kind?.contains(key) == true)
                    && (filter?(name, author, kind) ?? true)
            })
    }

    public func explore(url: String, page: Int = 1) async throws -> [SearchBook] {
        if isJsSource { return try jsSourceEngine().explore(url: url, page: page) }
        let context = WebBookContext(source: source, client: client, cookies: cookies)
        let response = try await context.request(url, baseURL: source.bookSourceUrl ?? "", bindings: ["page": page])
        return try await BookList.analyze(context: context, body: response.body, baseURL: response.url, isSearch: false)
    }

    public func bookInfo(_ result: SearchBook, canReName: Bool = false) async throws -> Book {
        var book = Book(now: now())
        book.bookUrl = result.bookUrl; book.name = result.name; book.author = result.author
        book.origin = result.origin; book.originName = result.originName; book.originOrder = result.originOrder
        book.type = result.type; book.kind = result.kind; book.intro = result.intro
        book.coverUrl = result.coverUrl; book.wordCount = result.wordCount
        book.latestChapterTitle = result.latestChapterTitle; book.variable = result.variable
        return try await bookInfo(book, canReName: canReName)
    }

    public func bookInfo(_ book: Book, canReName: Bool = false) async throws -> Book {
        try await bookInfoDetails(book, canReName: canReName).book
    }

    public func bookInfoDetails(_ book: Book, canReName: Bool = false) async throws -> BookInfo.Result {
        if isJsSource { return try jsSourceEngine().bookInfo(book, canReName: canReName) }
        let context = WebBookContext(source: source, client: client, book: book, cookies: cookies)
        let response = try await context.request(book.bookUrl ?? "", baseURL: source.bookSourceUrl ?? "")
        return try await BookInfo.analyzeDetails(context: context, book: book, body: response.body,
            baseURL: book.bookUrl ?? "", redirectURL: response.url, canReName: canReName)
    }

    public func chapterList(book: inout Book) async throws -> [BookChapter] {
        if LocalBook.isLocal(book) {
            let chapters = try LocalBook.chapterList(book: book)
            book.totalChapterNum = chapters.count
            book.latestChapterTitle = chapters.last?.title
            return chapters
        }
        let context = WebBookContext(source: source, client: client, book: book, cookies: cookies)
        let chapters: [BookChapter]
        if isJsSource { chapters = try jsSourceEngine().chapters(book: book) }
        else { chapters = try await BookChapterList.load(context: context, book: book, tocCountWords: tocCountWords) }
        let timestamp = now()
        if book.totalChapterNum < chapters.count {
            book.lastCheckCount = chapters.count - book.totalChapterNum
            book.latestChapterTime = timestamp
        }
        book.totalChapterNum = chapters.count; book.lastCheckTime = timestamp
        book.latestChapterTitle = try processor.title(book: book, chapter: chapters[chapters.count - 1])
        let current = chapters.indices.contains(book.durChapterIndex) ? book.durChapterIndex : chapters.count - 1
        book.durChapterTitle = try processor.title(book: book, chapter: chapters[current])
        return chapters
    }

    public func content(book: Book, chapter: BookChapter, nextChapterUrl: String? = nil,
                        includeTitle: Bool = true) async throws -> BookContent.Result {
        if isJsSource && !LocalBook.isLocal(book) {
            let raw = try jsSourceEngine().content(book: book, chapter: chapter, nextChapterUrl: nextChapterUrl)
            let processed = try processor.getContent(book: book, chapter: chapter, content: raw, includeTitle: includeTitle)
            return BookContent.Result(chapter: chapter, rawContent: raw, text: processed.text,
                paragraphs: processed.paragraphs, imageStyle: book.readConfig?.imageStyle ?? (source.bookSourceType == 2 ? "FULL" : nil), payAction: nil)
        }
        let context = WebBookContext(source: source, client: client, book: book, cookies: cookies)
        return try await BookContent.load(context: context, book: book, chapter: chapter,
            nextChapterURL: nextChapterUrl, processor: processor, includeTitle: includeTitle)
    }

    public func resolvePayAction(book: Book, chapter: BookChapter) async throws -> String {
        try Task.checkCancellation()
        guard let action = source.ruleContent?.payAction, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebBookError.missingRule("payAction")
        }
        let context = WebBookContext(source: source, client: client, book: book, cookies: cookies)
        let base = WebBookContext.absolute(chapter.url ?? "", base: chapter.baseUrl ?? book.tocUrl ?? "")
        let engine = try context.engine(baseURL: base)
        let bindings: [String: Any] = ["book": try WebBookContext.object(book),
            "chapter": try WebBookContext.object(chapter), "title": chapter.title ?? "", "baseUrl": base,
            "result": NSNull(), "src": NSNull()]
        let result: String
        if action.hasPrefix("http://") || action.hasPrefix("https://") {
            result = try AnalyzeUrlExecutor(action, engine: engine, bindings: bindings).url
        } else {
            result = ruleText(try engine.evaluateScript(action, bindings: bindings))
        }
        try Task.checkCancellation()
        return result
    }
}

final class WebBookContext {
    let source: BookSource
    let book: Book?
    let client: any HttpClient
    let bookStore: RuleVariableStore
    let sourceStore: RuleVariableStore
    let cookies: CookieStore
    let limiter = ConcurrentRateLimiter.shared

    init(source: BookSource, client: any HttpClient, book: Book? = nil, cookies: CookieStore = CookieStore()) {
        self.source = source; self.client = client; self.book = book
        self.cookies = cookies
        let values = book?.variable.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        bookStore = RuleVariableStore(values, name: book?.name ?? "")
        sourceStore = RuleVariableStore(name: source.bookSourceName ?? "")
    }

    func engine(baseURL: String) throws -> JsEngine {
        let engine = JsEngine(baseUrl: baseURL, httpClient: client, cookieStore: cookies,
            networkSource: .init(key: source.bookSourceUrl, enabledCookieJar: source.enabledCookieJar ?? true,
                                 concurrentRate: source.concurrentRate), rateLimiter: limiter)
        (client as? any SourceScriptClient)?.configureSourceBindings(engine)
        if let header = source.header, !header.isEmpty {
            let text = header.hasPrefix("@js:") ? ruleText(try engine.evaluateScript(String(header.dropFirst(4)))) : header
            engine.networkSource.headers = try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
        }
        if let library = source.jsLib, !library.isEmpty {
            engine.libraryInitializer = { context in
                context.evaluateScript(library)
                if let exception = context.exception { throw JsEngineError.exception(exception.toString()) }
            }
        }
        return engine
    }

    func parser(_ body: Any, baseURL: String, chapter: BookChapter? = nil, nextChapterURL: String? = nil) throws -> AnalyzeRule {
        let js = try engine(baseURL: baseURL)
        if let book {
            var value = try Self.object(book); value["name"] = bookStore.name
            js.bindings["book"] = value
        }
        if let chapter { js.bindings["chapter"] = try Self.object(chapter) }
        js.bindings["source"] = try Self.object(source)
        js.bindings["nextChapterUrl"] = nextChapterURL ?? ""
        let chapterStore = chapter.map { RuleVariableStore(name: $0.title ?? "") }
        let parser = AnalyzeRule(content: body, engines: [.default: AnalyzeByJSoup(), .xpath: AnalyzeByXPath(),
            .json: AnalyzeByJSonPath(), .js: js], chapter: chapterStore, book: bookStore, source: sourceStore)
        parser.scriptBaseUrl = baseURL
        return parser
    }

    func request(_ url: String, baseURL: String, bindings: [String: Any] = [:],
                 webJs: String? = nil, sourceRegex: String? = nil, forceWebView: Bool = false) async throws -> AnalyzeUrlExecutor.Response {
        try Task.checkCancellation()
        var values = bindings
        if let book { values["book"] = try Self.object(book) }
        values["source"] = try Self.object(source)
        let executor = try AnalyzeUrlExecutor(url, engine: engine(baseURL: baseURL), bindings: values)
        var response = try await executor.getStrResponse(jsStr: webJs, sourceRegex: sourceRegex, forceWebView: forceWebView)
        if let session = client as? any SourceScriptClient {
            let checked = try await session.checkResponse(StrResponse(raw: response.raw, body: response.body))
            response = .init(raw: checked.raw, body: checked.body, callTime: response.callTime)
        }
        try Task.checkCancellation()
        guard response.isSuccessful else { throw WebBookError.httpStatus(response.code, response.url) }
        return response
    }

    static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] ?? [:]
    }

    static func optional<T>(_ operation: () throws -> T) throws -> T? {
        do { return try operation() }
        catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            return nil
        }
    }

    static func url(_ parser: AnalyzeRule, rule: String?, base: String, redirect: String? = nil) throws -> String {
        let value = try parser.getString(rule, isURL: true)
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base : absolute(value, base: redirect ?? base)
    }

    var bookType: Int {
        switch source.bookSourceType {
        case 1: return 32
        case 2: return 64
        case 3: return 136
        case 4: return 4
        default: return 8
        }
    }

    static func wordCount(_ value: String) -> String {
        guard !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }), let count = Int32(value) else { return value }
        guard count > 0 else { return "" }
        guard count > 10000 else { return String(count) + "字" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false; formatter.roundingMode = .halfEven
        return (formatter.string(from: NSNumber(value: Double(Float(count)) / 10000)) ?? value) + "万字"
    }

    static func absolute(_ path: String, base: String) -> String {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let parts = UrlOptions.parse(value)
        let address = URL(string: parts.url, relativeTo: URL(string: UrlOptions.parse(base).url))?.absoluteURL.absoluteString ?? parts.url
        return address + String(value.dropFirst(parts.url.count))
    }

    static func flag(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && value != "null" && !["false", "no", "not", "0", "0.0"].contains(trimmed.lowercased())
    }

    static func name(_ value: String, author: Bool = false) -> String {
        let pattern = author ? #"^[ \t\n\r]*作[ \t\n\r]*者[:： \t\n\r]+|[ \t\n\r]+著"#
            : #"[ \t\n\r]+作[ \t\n\r]*者.*|[ \t\n\r]+\S+[ \t\n\r]+著"#
        return asciiTrim(value.replacingOccurrences(of: pattern, with: "", options: .regularExpression))
    }

    static func listRule(_ value: String?) -> (String, Bool) {
        var rule = value ?? ""
        let reverse = rule.hasPrefix("-")
        if reverse { rule.removeFirst() }
        if rule.hasPrefix("+") { rule.removeFirst() }
        return (rule, reverse)
    }

    func urls(_ parser: AnalyzeRule, rule: String?, base: String) throws -> [String] {
        var seen = Set<String>()
        return try (parser.getStringList(rule) ?? []).compactMap { value in
            let url = Self.absolute(value, base: base)
            return !url.isEmpty && url != base && seen.insert(url).inserted ? url : nil
        }
    }
}
