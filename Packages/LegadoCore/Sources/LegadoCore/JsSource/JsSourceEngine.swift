import Foundation

public final class JsSourceEngine {
    private let source: BookSource
    private let engine: JsEngine
    private let api: JsSourceApi

    public init(source: BookSource, client: any HttpClient = URLSessionHttpClient(),
                cookies: CookieStore = JsEngine.sharedCookieStore, api: JsSourceApi = JsSourceApi()) throws {
        self.source = source
        self.api = api
        engine = try WebBookContext(source: source, client: client, cookies: cookies).engine(baseURL: source.bookSourceUrl ?? "")
        let installer = engine.sourceBindingInstaller
        engine.sourceBindingInstaller = { [weak engine] context in
            try installer?(context)
            api.install(in: context, engine: engine)
        }
    }

    public func callFunction(_ name: String, arguments: [(String, Any)] = [], optional: Bool = false) throws -> String? {
        try Task.checkCancellation()
        guard let script = source.mainJs, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JsEngineError.exception("mainJs 为空,不是JS源")
        }
        let identifier = #"^[A-Za-z_$][A-Za-z0-9_$]*$"#
        guard ([name] + arguments.map(\.0)).allSatisfy({ $0.range(of: identifier, options: .regularExpression) != nil }) else {
            throw JsEngineError.exception("非法函数或参数名称")
        }
        var bindings: [String: Any] = ["source": try WebBookContext.object(source)]
        for (key, value) in arguments { bindings[key] = value }
        let invocation = """
        ;(function(){
          if(typeof \(name) !== 'function') {\(optional ? "return null;" : "throw new Error('JS源缺少函数 \(name)');")}
          var value=\(name)(\(arguments.map(\.0).joined(separator: ",")));
          return value == null ? null : typeof value === 'string' ? value : JSON.stringify(value);
        })();
        """
        return try engine.evaluateScript(script + "\n" + invocation, bindings: bindings) as? String
    }

    public func search(key: String, page: Int = 1) throws -> [SearchBook] {
        try books(callFunction("search", arguments: [("key", key), ("page", page)]))
    }

    public func explore(url: String, page: Int = 1) throws -> [SearchBook] {
        try books(callFunction("explore", arguments: [("url", url), ("page", page)]))
    }

    public func bookInfo(_ book: Book, canReName: Bool = false) throws -> BookInfo.Result {
        var fields = try WebBookContext.object(book)
        fields["type"] = (book.type & ~236) | sourceType
        var downloads: [String] = []
        if let json = try callFunction("getBookInfo", arguments: [("book", fields)], optional: true), !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let update = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
                throw JsEngineError.exception("getBookInfo 返回值不是对象")
            }
            for (key, value) in update where !(value is NSNull) {
                switch key {
                case "name": if canReName { fields[key] = value }
                case "author": if canReName || (book.author ?? "").isEmpty { fields[key] = value }
                case "intro", "coverUrl", "kind", "wordCount", "latestChapterTitle", "tocUrl": fields[key] = value
                case "type": if let type = value as? Int, validType(type) { fields[key] = type }
                case "variable":
                    let object = (value as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? value
                    if let map = object as? [String: Any], map.values.allSatisfy({ $0 is String || $0 is NSNumber }) {
                        fields[key] = String(decoding: try JSONSerialization.data(withJSONObject: map.mapValues { String(describing: $0) }, options: .sortedKeys), as: UTF8.self)
                    }
                case "downloadUrls":
                    if let urls = value as? [String] {
                        var seen = Set<String>()
                        downloads = urls.compactMap { value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("javascript") else { return nil }
                            let url = WebBookContext.absolute(trimmed, base: book.bookUrl ?? "")
                            return seen.insert(url).inserted ? url : nil
                        }
                    }
                default: break
                }
            }
        }
        var result = try GsonJSONDecoder().decode(Book.self, from: JSONSerialization.data(withJSONObject: fields))
        if source.bookSourceType == 3 { result.type |= sourceType }
        if result.type & 128 == 0, (result.tocUrl ?? "").isEmpty { result.tocUrl = result.bookUrl }
        if result.type & 128 != 0, downloads.isEmpty { throw WebBookError.emptyDownloadURLs }
        return BookInfo.Result(book: result, downloadURLs: downloads)
    }

    public func chapters(book: Book) throws -> [BookChapter] {
        let rows = try array(callFunction("getChapters", arguments: [("book", try WebBookContext.object(book))]), name: "getChapters")
        var chapters: [BookChapter] = []
        for row in rows {
            guard var chapter = try? GsonJSONDecoder().decode(BookChapter.self, from: JSONSerialization.data(withJSONObject: row)),
                  nonblank(chapter.title), nonblank(chapter.url) else { continue }
            if !(chapter.isVolume && chapter.url == chapter.title) {
                chapter.url = WebBookContext.absolute(chapter.url ?? "", base: book.tocUrl ?? "")
            }
            chapter.bookUrl = book.bookUrl; chapter.baseUrl = book.tocUrl; chapter.index = chapters.count
            chapters.append(chapter)
        }
        guard !chapters.isEmpty else { throw WebBookError.emptyToc }
        return chapters
    }

    public func content(book: Book, chapter: BookChapter, nextChapterUrl: String? = nil) throws -> String {
        if chapter.isVolume && (chapter.url ?? "").hasPrefix(chapter.title ?? "") { return "" }
        let value = try callFunction("getContent", arguments: [("chapter", try WebBookContext.object(chapter)),
            ("book", try WebBookContext.object(book)), ("nextChapterUrl", nextChapterUrl as Any? ?? NSNull())]) ?? ""
        if !chapter.isVolume && !nonblank(value) { throw WebBookError.emptyContent }
        return value
    }

    private var sourceType: Int { [0: 8, 1: 32, 2: 64, 3: 136, 4: 4][source.bookSourceType] ?? 8 }
    private func validType(_ type: Int) -> Bool { type != 0 && type & ~236 == 0 }
    private func nonblank(_ text: String?) -> Bool { !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func array(_ json: String?, name: String) throws -> [[String: Any]] {
        guard let json, nonblank(json) else { return [] }
        guard let values = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else {
            throw JsEngineError.exception("\(name) 返回值不是数组")
        }
        return values.compactMap { $0 as? [String: Any] }
    }

    private func books(_ json: String?) throws -> [SearchBook] {
        try array(json, name: "search/explore").compactMap { row in
            guard var book = try? GsonJSONDecoder().decode(SearchBook.self, from: JSONSerialization.data(withJSONObject: row)),
                  nonblank(book.name), nonblank(book.bookUrl) else { return nil }
            book.origin = source.bookSourceUrl; book.originName = source.bookSourceName; book.originOrder = source.customOrder
            book.type = (row["type"] as? Int).flatMap { validType($0) ? $0 : nil } ?? sourceType
            return book
        }
    }
}
