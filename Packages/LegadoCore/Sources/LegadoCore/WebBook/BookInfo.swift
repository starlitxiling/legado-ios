import Foundation

public enum BookInfo {
    public struct Result {
        public let book: Book
        public let downloadURLs: [String]
    }

    public static func analyzeDetails(source: BookSource, book: Book, body: String, baseURL: String,
                                      redirectURL: String? = nil, canReName: Bool = false) async throws -> Result {
        try await analyzeDetails(context: WebBookContext(source: source, client: ReplayHttpClient(), book: book),
            book: book, body: body, baseURL: baseURL, redirectURL: redirectURL, canReName: canReName)
    }
    public static func analyze(source: BookSource, book: Book, body: String, baseURL: String,
                               redirectURL: String? = nil, canReName: Bool = false) async throws -> Book {
        try await analyze(context: WebBookContext(source: source, client: ReplayHttpClient(), book: book),
                          book: book, body: body, baseURL: baseURL, redirectURL: redirectURL, canReName: canReName)
    }

    static func analyze(context: WebBookContext, book: Book, body: String, baseURL: String,
                        redirectURL: String? = nil, canReName: Bool = false) async throws -> Book {
        try await analyzeDetails(context: context, book: book, body: body, baseURL: baseURL,
                                 redirectURL: redirectURL, canReName: canReName).book
    }

    static func analyzeDetails(context: WebBookContext, book: Book, body: String, baseURL: String,
                               redirectURL: String? = nil, canReName: Bool = false) async throws -> Result {
        try Task.checkCancellation()
        let rule = context.source.ruleBookInfo ?? BookInfoRule()
        let parser = try context.parser(body, baseURL: baseURL)
        if let initial = rule.`init`, !initial.isEmpty { parser.setContent(try parser.getElement(initial)) }
        var result = book
        let rename = canReName && !(rule.canReName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let name = WebBookContext.name(try parser.getString(rule.name))
        if !name.isEmpty && (rename || (result.name ?? "").isEmpty) { result.name = name }
        context.bookStore.name = result.name ?? ""
        let author = WebBookContext.name(try parser.getString(rule.author), author: true)
        if !author.isEmpty && (rename || (result.author ?? "").isEmpty) { result.author = author }
        let kind = try WebBookContext.optional { try parser.getStringList(rule.kind)?.joined(separator: ",") ?? "" } ?? ""
        if !kind.isEmpty { result.kind = kind }
        let intro = try WebBookContext.optional { try parser.getString(rule.intro).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !intro.isEmpty {
            result.intro = ["<usehtml>", "<md>", "<useweb>"].contains(where: intro.hasPrefix) ? intro : HtmlFormatter.formatIntro(intro)
        }
        let latest = try WebBookContext.optional { try parser.getString(rule.lastChapter) } ?? ""
        if !latest.isEmpty { result.latestChapterTitle = latest }
        let words = try WebBookContext.optional { WebBookContext.wordCount(try parser.getString(rule.wordCount)) } ?? ""
        if !words.isEmpty { result.wordCount = words }
        let cover = try WebBookContext.optional { WebBookContext.absolute(try parser.getString(rule.coverUrl), base: redirectURL ?? baseURL) } ?? ""
        if !cover.isEmpty { result.coverUrl = cover }
        var downloads: [String] = []
        if book.type & 128 != 0 || context.source.bookSourceType == 3 {
            downloads = try (parser.getStringList(rule.downloadUrls) ?? []).map {
                WebBookContext.absolute($0, base: redirectURL ?? baseURL)
            }.filter { !$0.isEmpty }
            guard !downloads.isEmpty else { throw WebBookError.emptyDownloadURLs }
        } else {
            result.tocUrl = try WebBookContext.url(parser, rule: rule.tocUrl, base: baseURL, redirect: redirectURL)
        }
        result.origin = context.source.bookSourceUrl; result.originName = context.source.bookSourceName
        try Task.checkCancellation()
        return Result(book: result, downloadURLs: downloads)
    }
}
