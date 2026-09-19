import Foundation

public enum WebBookError: Error, Equatable {
    case missingRule(String)
    case emptyToc
    case emptyContent
    case bookNotFound(String, String)
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
    private let configuration: WebBookConfiguration
    private let jsSourceApi = JsSourceApi()

    private var isJsSource: Bool {
        !(source.mainJs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func jsSourceEngine() throws -> JsSourceEngine {
        try JsSourceEngine(source: source, client: client, cookies: cookies, api: jsSourceApi)
    }

    public convenience init(source: BookSource, client: any HttpClient, replaceRules: [ReplaceRule] = [],
                            precisionSearch: Bool = false, tocCountWords: Bool = false, configuration: WebBookConfiguration = .init(),
                            now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.init(source: source, client: client, replaceRules: replaceRules, precisionSearch: precisionSearch,
                  tocCountWords: tocCountWords, cookies: CookieStore(), configuration: configuration, now: now)
    }

    public init(source: BookSource, client: any HttpClient, replaceRules: [ReplaceRule] = [],
                precisionSearch: Bool = false, tocCountWords: Bool = false, cookies: CookieStore,
                configuration: WebBookConfiguration = .init(),
                now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.source = source
        self.client = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
        self.processor = ContentProcessor(rules: replaceRules, adaptSpecialStyle: configuration.adaptSpecialStyle, cacheDirectory: configuration.cacheDirectory)
        self.now = now
        self.precisionSearch = precisionSearch
        self.tocCountWords = tocCountWords
        self.cookies = cookies
        self.configuration = configuration
    }

    public func checkKeyword(default fallback: String) -> String {
        guard let value = source.ruleSearch?.checkKeyWord,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !["http", "::", "++", "--"].contains(where: value.contains) else { return fallback }
        return value
    }

    public func search(key: String, page: Int = 1,
                       filter: BookList.Filter? = nil, shouldBreak: ((Int) -> Bool)? = nil) async throws -> [SearchBook] {
        if isJsSource {
            var results: [SearchBook] = []
            for book in try jsSourceEngine().search(key: key, page: page) {
                if (!precisionSearch || (book.name ?? "").contains(key) || (book.author ?? "").contains(key) || book.kind?.contains(key) == true)
                    && (filter?(book.name ?? "", book.author ?? "", book.kind) ?? true) { results.append(book) }
                if shouldBreak?(results.count) == true { break }
            }
            return results
        }
        guard let url = source.searchUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebBookError.missingRule("searchUrl")
        }
        let context = try WebBookContext(source: source, client: client, cookies: cookies, sourceAPI: jsSourceApi, configuration: configuration)
        let response = try await context.request(url, baseURL: source.bookSourceUrl ?? "",
                                                 bindings: ["key": key, "page": page])
        return try await BookList.analyze(context: context, body: response.body, baseURL: response.url,
            requestURL: response.requestURL, ruleURL: response.ruleURL, isRedirected: response.isRedirected,
            isSearch: true, filter: { name, author, kind in
                (!self.precisionSearch || name.contains(key) || author.contains(key) || kind?.contains(key) == true)
                    && (filter?(name, author, kind) ?? true)
            }, shouldBreak: shouldBreak)
    }

    public func explore(url: String, page: Int = 1) async throws -> [SearchBook] {
        if isJsSource { return try jsSourceEngine().explore(url: url, page: page) }
        let context = try WebBookContext(source: source, client: client, cookies: cookies, sourceAPI: jsSourceApi, configuration: configuration)
        let response = try await context.request(url, baseURL: source.bookSourceUrl ?? "", bindings: ["page": page])
        return try await BookList.analyze(context: context, body: response.body, baseURL: response.url,
            requestURL: response.requestURL, ruleURL: response.ruleURL, isRedirected: response.isRedirected, isSearch: false)
    }

    public func bookInfo(_ result: SearchBook, canReName: Bool = false) async throws -> Book {
        try await bookInfo(result.toBook(now: now()), canReName: canReName)
    }

    public func preciseSearch(name: String, author: String) async throws -> Book {
        let results = try await search(key: name, filter: { foundName, foundAuthor, _ in foundName == name && foundAuthor == author }, shouldBreak: { $0 > 0 })
        guard let result = results.first else { throw WebBookError.bookNotFound(name, author) }
        return result.toBook(now: now())
    }

    public func bookInfo(_ book: Book, canReName: Bool = false) async throws -> Book {
        try await bookInfoDetails(book, canReName: canReName).book
    }

    public func bookInfoDetails(_ book: Book, canReName: Bool = false) async throws -> BookInfo.Result {
        if isJsSource { return try jsSourceEngine().bookInfo(book, canReName: canReName) }
        let context = try WebBookContext(source: source, client: client, book: book, cookies: cookies, sourceAPI: jsSourceApi, configuration: configuration)
        if let body = book.infoHtml, !body.isEmpty {
            return try await BookInfo.analyzeDetails(context: context, book: book, body: body,
                baseURL: book.bookUrl ?? "", redirectURL: book.bookUrl, canReName: canReName)
        }
        let response = try await context.request(book.bookUrl ?? "", baseURL: source.bookSourceUrl ?? "")
        return try await BookInfo.analyzeDetails(context: context, book: book, body: response.body,
            baseURL: book.bookUrl ?? "", redirectURL: response.url, canReName: canReName)
    }

    public func chapterList(book: inout Book, previousChapters: [BookChapter] = [],
                            runPreUpdate: Bool = false, fromBookInfo: Bool = false) async throws -> [BookChapter] {
        if LocalBook.isLocal(book) {
            let chapters = try LocalBook.chapterList(book: book)
            book.totalChapterNum = chapters.count
            book.latestChapterTitle = chapters.last?.title
            return chapters
        }
        let context = try WebBookContext(source: source, client: client, book: book, cookies: cookies, sourceAPI: jsSourceApi, configuration: configuration)
        var chapters: [BookChapter]
        if isJsSource { chapters = try jsSourceEngine().chapters(book: book) }
        else { chapters = try await BookChapterList.load(context: context, book: book, tocCountWords: tocCountWords,
            runPreUpdate: runPreUpdate, fromBookInfo: fromBookInfo) }
        if !isJsSource { book = try context.bookStore.snapshot() }
        chapters = BookChapterList.upChapterInfo(chapters, previous: previousChapters, enabled: tocCountWords)
        let timestamp = now()
        if book.totalChapterNum < chapters.count {
            book.lastCheckCount = chapters.count - book.totalChapterNum
            book.latestChapterTime = timestamp
        }
        book.totalChapterNum = chapters.count; book.lastCheckTime = timestamp
        let simulatedIndex = book.simulatedTotalChapterNum(now: Date(timeIntervalSince1970: Double(timestamp) / 1000)) - 1
        book.latestChapterTitle = try processor.title(book: book, chapter: chapters[chapters.indices.contains(simulatedIndex) ? simulatedIndex : chapters.count - 1])
        let current = chapters.indices.contains(book.durChapterIndex) ? book.durChapterIndex : chapters.count - 1
        book.durChapterTitle = try processor.title(book: book, chapter: chapters[current])
        return chapters
    }

    public func content(book: Book, chapter: BookChapter, nextChapterUrl: String? = nil,
                        includeTitle: Bool = true) async throws -> BookContent.Result {
        try await BookContent.cached(source: source, book: book, chapter: chapter, client: client, cookies: cookies,
            configuration: configuration, processor: processor, includeTitle: includeTitle) {
            if isJsSource && !LocalBook.isLocal(book) {
                let raw = try jsSourceEngine().content(book: book, chapter: chapter, nextChapterUrl: nextChapterUrl)
                let processed = try processor.getContent(book: book, chapter: chapter, content: raw, includeTitle: includeTitle)
                return BookContent.Result(chapter: chapter, rawContent: raw, text: processed.text,
                    paragraphs: processed.paragraphs, imageStyle: book.readConfig?.imageStyle ?? source.ruleContent?.imageStyle ?? (source.bookSourceType == 2 ? "FULL" : nil), payAction: source.ruleContent?.payAction)
            }
            let context = try WebBookContext(source: source, client: client, book: book, cookies: cookies, sourceAPI: jsSourceApi, configuration: configuration)
            return try await BookContent.load(context: context, book: book, chapter: chapter,
                nextChapterURL: nextChapterUrl, processor: processor, includeTitle: includeTitle)
        }
    }

    public func contentBatch(book: Book, chapters: [BookChapter]) async throws -> [BookChapter] {
        try Task.checkCancellation()
        guard !chapters.isEmpty else { return [] }
        guard let directory = configuration.cacheDirectory else { throw WebBookError.missingRule("cacheDirectory") }
        let script = source.ruleContent?.contentBatch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isJsSource || !script.isEmpty else { throw WebBookError.missingRule("contentBatch") }
        let context = try WebBookContext(source: source, client: client, book: book, cookies: cookies,
            sourceAPI: jsSourceApi, configuration: configuration)
        let base = (book.tocUrl ?? "").isEmpty ? source.bookSourceUrl ?? "" : book.tocUrl ?? ""
        let engine = try context.engine(baseURL: base)
        let parser = try context.parser("", baseURL: base, chapter: chapters.first, engine: engine)
        let batch = try BatchContentContext(chapters: chapters, context: context, book: book, directory: directory)
        parser.batchContent = batch
        defer { batch.close(); parser.batchContent = nil }
        let values = try chapters.map(WebBookContext.object)
        try await context.limiter.acquire(key: source.bookSourceUrl, rate: source.concurrentRate)
        if isJsSource {
            _ = try engine.evaluateScript((source.mainJs ?? "") + "\n;if(typeof getContentBatch === 'function') getContentBatch(chapters, book);",
                bindings: ["chapters": values], context: parser)
        } else if script.lowercased().hasPrefix("<js>") || script.lowercased().hasPrefix("@js:") {
            for rule in try parser.splitSourceRule(script) {
                guard rule.mode == .js else { throw JsEngineError.exception("contentBatch only accepts JavaScript") }
                _ = try engine.evaluateScript(rule.rule, bindings: ["result": values], context: parser)
            }
        } else { _ = try engine.evaluateScript(script, bindings: ["result": values], context: parser) }
        try Task.checkCancellation()
        return batch.missingChapters()
    }

    public func resolvePayAction(book: Book, chapter: BookChapter) async throws -> String {
        try Task.checkCancellation()
        guard let action = source.ruleContent?.payAction, !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebBookError.missingRule("payAction")
        }
        let context = try WebBookContext(source: source, client: client, book: book, cookies: cookies, sourceAPI: jsSourceApi, configuration: configuration)
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
    let bookStore: JsBookBinding
    let sourceStore: JsSourceBinding
    private var chapterStores: [String: JsChapterBinding] = [:]
    let cookies: CookieStore
    let configuration: WebBookConfiguration
    let limiter = ConcurrentRateLimiter.shared

    init(source: BookSource, client: any HttpClient, book: Book? = nil, cookies: CookieStore = CookieStore(),
         sourceAPI: JsSourceApi = JsSourceApi(), configuration: WebBookConfiguration = .init()) throws {
        self.configuration = configuration
        self.source = source; self.client = client; self.book = book
        self.cookies = cookies
        bookStore = try JsBookBinding(book ?? Book(now: 0))
        sourceStore = JsSourceBinding(source, api: sourceAPI)
        (client as? any SourceScriptClient)?.configureSourceVariables(sourceStore)
    }

    func chapterBinding(_ chapter: BookChapter) throws -> JsChapterBinding {
        let key = "\(chapter.index)|\(chapter.url ?? "")"
        if let binding = chapterStores[key] { return binding }
        let binding = try JsChapterBinding(chapter)
        chapterStores[key] = binding
        return binding
    }

    func engine(baseURL: String) throws -> JsEngine {
        let engine = JsEngine(baseUrl: baseURL, httpClient: client, cookieStore: cookies,
            networkSource: .init(key: source.bookSourceUrl, enabledCookieJar: source.enabledCookieJar ?? true,
                                 concurrentRate: source.concurrentRate), rateLimiter: limiter, headlessWebView: configuration.headlessWebView)
        engine.bindings["source"] = try sourceStore.scriptObject()
        if book != nil { engine.bindings["book"] = try bookStore.scriptObject() }
        if let session = client as? any SourceScriptClient { session.configureSourceBindings(engine) }
        else {
            let api = sourceStore.api
            engine.sourceBindingInstaller = { [weak engine] context in api.install(in: context, engine: engine) }
        }
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

    func parser(_ body: Any, baseURL: String, chapter: BookChapter? = nil, nextChapterURL: String? = nil,
                chapterBinding: JsChapterBinding? = nil, fromBookInfo: Bool = false,
                engine: JsEngine? = nil) throws -> AnalyzeRule {
        let js = try engine ?? self.engine(baseURL: baseURL)
        js.bindings.removeValue(forKey: "book")
        let chapterStore = try chapterBinding ?? chapter.map { try self.chapterBinding($0) }
        let parser = AnalyzeRule(content: body, engines: [.default: AnalyzeByJSoup(), .xpath: AnalyzeByXPath(),
            .json: AnalyzeByJSonPath(), .js: js], chapter: chapterStore, book: book == nil ? nil : bookStore,
            ruleData: bookStore, source: sourceStore)
        parser.contextBindings = ["nextChapterUrl": nextChapterURL ?? "", "fromBookInfo": fromBookInfo,
                                  "isFromBookInfo": fromBookInfo]
        parser.setBaseUrl(baseURL)
        parser.setRedirectUrl(baseURL)
        js.variableContext = parser
        return parser
    }

    func request(_ url: String, baseURL: String, bindings: [String: Any] = [:], chapter: BookChapter? = nil,
                 webJs: String? = nil, sourceRegex: String? = nil, forceWebView: Bool = false) async throws -> AnalyzeUrlExecutor.Response {
        try Task.checkCancellation()
        let js = try engine(baseURL: baseURL)
        let parser = try parser("", baseURL: baseURL, chapter: chapter, engine: js)
        let executor = try AnalyzeUrlExecutor(url, engine: js, bindings: bindings, context: parser)
        func check(_ response: AnalyzeUrlExecutor.Response) async throws -> AnalyzeUrlExecutor.Response {
            let text = StrResponse(raw: response.raw, body: response.body)
            let checked: StrResponse
            if let session = client as? any SourceScriptClient { checked = try await session.checkResponse(text) }
            else {
                checked = try await SourceResponseCheck.check(source: source, response: text) { script, bindings in
                    try js.evaluateScript(script, bindings: bindings, context: parser)
                }
            }
            return .init(raw: checked.raw, body: checked.body, callTime: response.callTime,
                requestURL: executor.url, ruleURL: executor.ruleURL, isRedirected: response.url != executor.url)
        }
        let response: AnalyzeUrlExecutor.Response
        do {
            let received = try await executor.getStrResponse(jsStr: webJs, sourceRegex: sourceRegex, forceWebView: forceWebView)
            response = try await check(received)
        } catch {
            let original = error
            try Task.checkCancellation()
            guard !(original is CancellationError), (original as? URLError)?.code != .cancelled,
                  !(source.loginCheckJs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let address = URL(string: executor.url) else { throw original }
            let message = String(describing: original)
            let failed = AnalyzeUrlExecutor.Response(raw: HttpResponse(status: 500, body: Data(message.utf8), finalURL: address), body: message)
            do {
                let recovered = try await check(failed)
                guard recovered.code != 500 else { throw original }
                response = recovered
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                throw original
            }
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
        parser.setBaseUrl(base)
        parser.setRedirectUrl(redirect ?? base)
        guard let rule, !rule.isEmpty else { return base }
        return try parser.getString(rule, isURL: true)
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
        parser.setRedirectUrl(base)
        return try parser.getStringList(rule, isURL: true) ?? []
    }
}
