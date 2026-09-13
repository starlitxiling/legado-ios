import Foundation

public final class WebApi: Sendable {
    public static let routes: [String: String] = [
        "/getBookshelf": "GET", "/getChapterList": "GET", "/refreshToc": "GET", "/getBookContent": "GET",
        "/cover": "GET", "/image": "GET", "/addLocalBook": "POST",
        "/saveBook": "POST", "/deleteBook": "POST", "/saveBookProgress": "POST",
        "/getBookSources": "GET", "/getBookSource": "GET", "/saveBookSource": "POST",
        "/saveBookSources": "POST", "/deleteBookSources": "POST", "/getReplaceRules": "GET",
        "/saveReplaceRule": "POST", "/deleteReplaceRule": "POST", "/testReplaceRule": "POST",
        "/getReadConfig": "GET", "/saveReadConfig": "POST",
        "/getRssSources": "GET", "/getRssSource": "GET", "/saveRssSource": "POST",
        "/saveRssSources": "POST", "/deleteRssSources": "POST"
    ]
    private let books: BookshelfRepository
    private let sources: BookSourceRepository
    private let chapters: ChapterRepository
    private let rules: ReplaceRuleRepository
    private let state: SourceStateRepository
    private let client: (any HttpClient)?
    private let cacheDirectory: URL?
    private let rss: RssRepository
    private let database: AppDatabase
    private let bookshelfSort: @Sendable () -> Int
    private let booksDirectory: URL?

    public init(database: AppDatabase, client: (any HttpClient)? = nil, cacheDirectory: URL? = nil, bookshelfSort: @escaping @Sendable () -> Int = { 0 }, booksDirectory: URL? = nil) {
        self.database = database; self.bookshelfSort = bookshelfSort; self.booksDirectory = booksDirectory
        books = .init(database: database); sources = .init(database: database)
        chapters = .init(database: database); rules = .init(database: database)
        state = .init(database: database); self.client = client; self.cacheDirectory = cacheDirectory; self.rss = RssRepository(database: database)
    }

    public func handle(_ request: WebHttpRequest) async -> WebHttpResponse {
        do {
            switch request.path {
            case "/getBookshelf":
                var values = try await books.all()
                switch bookshelfSort() {
                case 1: values.sort { $0.latestChapterTime > $1.latestChapterTime }
                case 2: values.sort { $0.name.compare($1.name, locale: Locale(identifier: "zh_CN")) == .orderedAscending }
                case 3: values.sort { $0.order < $1.order }
                default: values.sort { $0.durChapterTime > $1.durChapterTime }
                }
                guard !values.isEmpty else { throw ApiError("还没有添加小说") }
                return try success(values.map { try WebApiCodec.entity($0, as: Book.self) })
            case "/cover", "/image":
                return try await image(request)
            case "/addLocalBook":
                let upload = try WebBookUpload.parse(request)
                guard let booksDirectory else { throw ApiError("需重新设置书籍保存位置!") }
                try await WebBookUpload.save(upload, directory: booksDirectory, database: database)
                return try success(true)
            case "/saveBook", "/deleteBook":
                guard let book = try? JSONDecoder().decode(Book.self, from: request.body), let url = book.bookUrl, !url.isEmpty else { throw ApiError("格式不对") }
                if request.path == "/deleteBook" {
                    if let row = try await books.get(bookUrl: url) { try await books.delete(row) }
                } else if let existing = try await books.get(bookUrl: url) {
                    try await books.upsert(WebApiCodec.row(book, defaults: existing))
                } else { try await books.replaceByIdentity([WebApiCodec.row(book, defaults: BookRow())]) }
                return try success("")
            case "/saveBookProgress":
                guard let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let name = object["name"] as? String, let author = object["author"] as? String,
                      let index = object["durChapterIndex"] as? Int, let pos = object["durChapterPos"] as? Int,
                      let time = object["durChapterTime"] as? Int64,
                      let row = try await books.all().first(where: { $0.name == name && $0.author == author }) else { throw ApiError("格式不对") }
                try await books.updateProgress(bookUrl: row.bookUrl, chapterIndex: index, chapterPos: pos,
                                               chapterTitle: object["durChapterTitle"] as? String, readTime: time)
                return try success("")
            case "/getChapterList", "/refreshToc":
                let url = try parameter(request, "url", "参数url不能为空，请指定书籍地址")
                let existing = try await chapters.list(bookUrl: url)
                if request.path == "/getChapterList", !existing.isEmpty {
                    return try success(existing.map { try WebApiCodec.entity($0, as: BookChapter.self) })
                }
                guard let row = try await books.get(bookUrl: url) else { throw ApiError("未在数据库找到对应书籍，请先添加") }
                var book = try WebApiCodec.entity(row, as: Book.self)
                let toc: [BookChapter]
                if LocalBook.isLocal(book) { toc = try LocalBook.chapterList(book: book) }
                else {
                    let web = try await webBook(book)
                    if (book.tocUrl ?? "").isEmpty { book = try await web.bookInfo(book) }
                    toc = try await web.chapterList(book: &book)
                }
                try await chapters.replaceAll(bookUrl: url, chapters: toc.map { try WebApiCodec.row($0, defaults: BookChapterRow()) })
                try await books.upsert(WebApiCodec.row(book, defaults: row))
                return try success(toc)
            case "/getBookContent":
                let url = try parameter(request, "url", "参数url不能为空，请指定书籍地址")
                guard let value = request.query["index"]?.first, let index = Int(value), index >= 0 else { throw ApiError("参数index不能为空, 请指定目录序号") }
                guard let row = try await books.get(bookUrl: url), let chapterRow = try await chapters.get(bookUrl: url, index: index) else { throw ApiError("未找到") }
                let book = try WebApiCodec.entity(row, as: Book.self)
                let chapter = try WebApiCodec.entity(chapterRow, as: BookChapter.self)
                let replacements = try await rules.all().map { try WebApiCodec.entity($0, as: ReplaceRule.self) }
                let raw: String?
                if LocalBook.isLocal(book) { raw = try LocalBook.content(book: book, chapter: chapter) }
                else if let cacheDirectory { raw = try BookHelp.content(directory: cacheDirectory, book: book, chapter: chapter) }
                else { raw = nil }
                if let raw {
                    return try success(ContentProcessor(rules: replacements).getContent(book: book, chapter: chapter, content: raw, includeTitle: false).text)
                }
                let web = try await webBook(book, replacements: replacements)
                let next = try await chapters.get(bookUrl: url, index: index + 1)
                return try await success(web.content(book: book, chapter: chapter, nextChapterUrl: next?.url, includeTitle: false).text)
            case "/getBookSources":
                let values = try await sources.list()
                guard !values.isEmpty else { throw ApiError("设备源列表为空") }
                return try success(values.map { try WebApiCodec.entity($0, as: BookSource.self) })
            case "/getBookSource":
                let url = try parameter(request, "url", "参数url不能为空，请指定源地址")
                guard let source = try await sources.get(bookSourceUrl: url) else { throw ApiError("未找到源，请检查书源地址") }
                return try success(WebApiCodec.entity(source, as: BookSource.self))
            case "/saveBookSource":
                guard !request.body.isEmpty else { throw ApiError("数据不能为空") }
                guard let source = try? JSONDecoder().decode(BookSource.self, from: request.body) else { throw ApiError("转换源失败") }
                guard !(source.bookSourceName ?? "").isEmpty, !(source.bookSourceUrl ?? "").isEmpty else { throw ApiError("源名称和URL不能为空") }
                try await sources.upsert(WebApiCodec.row(source, defaults: BookSourceRow()))
                return try success("")
            case "/saveBookSources", "/deleteBookSources":
                guard !request.body.isEmpty else { throw ApiError("数据为空") }
                guard let values = try? JSONDecoder().decode([BookSource].self, from: request.body) else { throw ApiError("转换源失败") }
                if request.path == "/deleteBookSources" {
                    for source in values {
                        if let row = try await sources.get(bookSourceUrl: source.bookSourceUrl ?? "") { try await sources.delete(row) }
                    }
                    return try success("已执行")
                }
                guard !values.isEmpty else { throw ApiError("转换源失败") }
                let valid = values.filter { !($0.bookSourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !($0.bookSourceUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                try await sources.upsert(valid.map { try WebApiCodec.row($0, defaults: BookSourceRow()) })
                return try success(valid)
            case "/getReplaceRules":
                let values = try await rules.list().map { try WebApiCodec.entity($0, as: ReplaceRule.self) }
                return try success(String(decoding: JSONEncoder().encode(values), as: UTF8.self))
            case "/testReplaceRule":
                guard !request.body.isEmpty else { throw ApiError("数据不能为空") }
                guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                      let input = object["rule"], let text = object["text"] as? String else { throw ApiError("格式不对") }
                let data = try (input as? String).map { Data($0.utf8) }
                    ?? JSONSerialization.data(withJSONObject: input, options: [.fragmentsAllowed])
                guard let rule = try? JSONDecoder().decode(ReplaceRule.self, from: data) else { throw ApiError("格式不对") }
                do { return try success(ContentProcessor().apply(rule, to: text)) }
                catch { return try success(String(reflecting: error)) }
            case "/saveReplaceRule", "/deleteReplaceRule":
                guard !request.body.isEmpty else { throw ApiError("数据不能为空") }
                guard let rule = try? JSONDecoder().decode(ReplaceRule.self, from: request.body) else { throw ApiError("格式不对") }
                var row = try WebApiCodec.row(rule, defaults: ReplaceRuleRow())
                if request.path == "/deleteReplaceRule" { try await rules.delete(row) }
                else {
                    let old = try await rules.get(id: rule.id)
                    if let sample = rule.previewText {
                        var units = Array(sample.utf16.prefix(300))
                        if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
                        let normalized = String(decoding: units, as: UTF16.self)
                        row.previewText = normalized.isEmpty ? nil : normalized
                    } else if old?.pattern == row.pattern && old?.replacement == row.replacement {
                        row.previewText = old?.previewText
                    }
                    if row.order == Int(Int32.min) { row.order = try await (rules.all().map(\.order).max() ?? -1) + 1 }
                    try await rules.upsert(row)
                }
                // Android 此两条写接口未调用 setData，成功写入也保留默认 ReturnData。
                return try failure("未知错误,请联系开发者!")
            case "/getReadConfig":
                guard let value = try await state.load(source: "legado-ios:web-config")["readConfig"] else { throw ApiError("没有配置") }
                return try success(value)
            case "/saveReadConfig":
                try await state.save(source: "legado-ios:web-config", values: request.body.isEmpty ? [:] : ["readConfig": String(decoding: request.body, as: UTF8.self)])
                return try success("")
            case let path where path.contains("RssSource"):
                return try await handleRss(request)
            default: return try failure("Not Found", status: 404)
            }
        } catch {
            return (try? failure((error as? ApiError)?.message ?? error.localizedDescription))
                ?? WebHttpResponse(status: 400, body: Data())
        }
    }

    private func image(_ request: WebHttpRequest) async throws -> WebHttpResponse {
        let cover = request.path == "/cover"
        var book: Book?
        var source: BookSource?
        if !cover {
            let url = try parameter(request, "url", "bookUrl为空")
            guard let row = try await books.get(bookUrl: url) else { throw ApiError("bookUrl不对") }
            book = try WebApiCodec.entity(row, as: Book.self)
            source = try await sources.get(bookSourceUrl: row.origin).map { try WebApiCodec.entity($0, as: BookSource.self) }
        }
        let path = request.query["path"]?.first
        if !cover && path == nil { throw ApiError("图片链接为空") }
        let width = cover ? 84 : Int(request.query["width"]?.first ?? "640")
        guard let width, (1...4096).contains(width) else { throw ApiError("width 格式不正确") }
        var bytes: Data?
        do {
            if let path {
                if cover, let url = URL(string: path), url.isFileURL {
                    guard try await books.all().contains(where: { $0.coverUrl == path || $0.customCoverUrl == path }) else { throw ApiError("未找到封面") }
                    bytes = try Data(contentsOf: url)
                } else {
                    guard let client else { throw ApiError("网络客户端未配置") }
                    bytes = try await ImageDownloader(client: client, cacheDirectory: cacheDirectory?.appendingPathComponent("web-images"))
                        .load(url: path, source: source, book: book, isCover: cover)
                }
            }
        } catch { if !cover { throw error } }
        return WebHttpResponse(contentType: "image/png", body: try WebImageRenderer.png(bytes, width: width, cover: cover))
    }

    private func handleRss(_ request: WebHttpRequest) async throws -> WebHttpResponse {
        switch request.path {
        case "/getRssSources":
            let values = try await rss.sources()
            guard !values.isEmpty else { throw ApiError("源列表为空") }
            return try success(values)
        case "/getRssSource":
            let url = try parameter(request, "url", "参数url不能为空，请指定书源地址")
            guard let source = try await rss.sources().first(where: { $0.sourceUrl == url }) else { throw ApiError("未找到源，请检查源地址") }
            return try success(source)
        case "/saveRssSource":
            guard !request.body.isEmpty else { throw ApiError("数据不能为空") }
            guard let source = try? JSONDecoder().decode(RssSource.self, from: request.body) else { throw ApiError("转换源失败") }
            guard !source.sourceName.isEmpty, !source.sourceUrl.isEmpty else { throw ApiError("源名称和URL不能为空") }
            try await rss.saveSources([source])
            return try success("")
        case "/saveRssSources", "/deleteRssSources":
            guard !request.body.isEmpty else { throw ApiError(request.path == "/deleteRssSources" ? "没有传递数据" : "数据不能为空") }
            guard let values = try? JSONDecoder().decode([RssSource].self, from: request.body) else { throw ApiError("格式不对") }
            if request.path == "/deleteRssSources" {
                for source in values { try await rss.deleteSource(source.sourceUrl) }
                return try success("已执行")
            }
            guard !values.isEmpty else { throw ApiError("转换源失败") }
            let valid = values.filter { !$0.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            try await rss.saveSources(valid)
            return try success(valid)
        default: return try failure("Not Found", status: 404)
        }
    }

    private func parameter(_ request: WebHttpRequest, _ key: String, _ message: String) throws -> String {
        guard let value = request.query[key]?.first, !value.isEmpty else { throw ApiError(message) }
        return value
    }

    private func webBook(_ book: Book, replacements: [ReplaceRule] = []) async throws -> WebBook {
        guard let source = try await sources.get(bookSourceUrl: book.origin ?? "") else { throw ApiError("未找到书源") }
        guard let client else { throw ApiError("网络客户端未配置") }
        return WebBook(source: try WebApiCodec.entity(source, as: BookSource.self), client: client, replaceRules: replacements)
    }

    private func success<T: Encodable>(_ value: T) throws -> WebHttpResponse {
        WebHttpResponse(body: try JSONEncoder().encode(ReturnData(data: value)))
    }

    private func failure(_ message: String, status: Int = 200) throws -> WebHttpResponse {
        WebHttpResponse(status: status, body: try JSONEncoder().encode(ReturnData<String>(errorMsg: message)))
    }

    private struct ApiError: Error { let message: String; init(_ message: String) { self.message = message } }
}

/// HTTP 使用实体 JSON，数据库复合列使用 JSON 文本。
enum WebApiCodec {
    static let compositeKeys = ["readConfig", "ruleExplore", "ruleSearch", "ruleBookInfo", "ruleToc", "ruleContent", "ruleReview"]

    static func entity<Row: Encodable, Value: Decodable>(_ row: Row, as: Value.Type) throws -> Value {
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as! [String: Any]
        for key in compositeKeys {
            if let text = fields[key] as? String { fields[key] = try JSONSerialization.jsonObject(with: Data(text.utf8)) }
        }
        if Row.self == ReplaceRuleRow.self { fields["order"] = fields.removeValue(forKey: "sortOrder") }
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    static func row<Value: Encodable, Row: StorageRow>(_ value: Value, defaults: Row) throws -> Row {
        let encoder = JSONEncoder()
        var fields = try JSONSerialization.jsonObject(with: encoder.encode(defaults)) as! [String: Any]
        let incoming = try JSONSerialization.jsonObject(with: encoder.encode(value)) as! [String: Any]
        for (key, value) in incoming {
            let column = Row.self == ReplaceRuleRow.self && key == "order" ? "sortOrder" : key
            if compositeKeys.contains(key), !(value is NSNull) {
                fields[column] = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self)
            } else { fields[column] = value }
        }
        return try JSONDecoder().decode(Row.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
