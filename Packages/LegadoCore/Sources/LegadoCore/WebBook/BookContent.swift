import Foundation

public enum BookContent {
    public struct Result {
        public let chapter: BookChapter
        public let rawContent: String
        public let text: String
        public let paragraphs: [String]
        public let imageStyle: String?
        public let payAction: String?
    }

    public static func load(source: BookSource, book: Book, chapter: BookChapter, client: any HttpClient,
                            nextChapterURL: String? = nil, processor: ContentProcessor = ContentProcessor(),
                            includeTitle: Bool = true) async throws -> Result {
        try await load(context: WebBookContext(source: source, client: client, book: book), book: book,
            chapter: chapter, nextChapterURL: nextChapterURL, processor: processor, includeTitle: includeTitle)
    }

    static func load(context: WebBookContext, book: Book, chapter: BookChapter, nextChapterURL: String?,
                     processor: ContentProcessor, includeTitle: Bool) async throws -> Result {
        try Task.checkCancellation()
        let rule = context.source.ruleContent ?? ContentRule()
        func finish(_ text: String, chapter: BookChapter) throws -> Result {
            let processed = try processor.getContent(book: book, chapter: chapter, content: text, includeTitle: includeTitle)
            return Result(chapter: chapter, rawContent: text, text: processed.text, paragraphs: processed.paragraphs,
                          imageStyle: book.readConfig?.imageStyle ?? rule.imageStyle ?? (context.source.bookSourceType == 2 ? "FULL" : nil),
                          payAction: rule.payAction)
        }
        if LocalBook.isLocal(book) { return try finish(LocalBook.content(book: book, chapter: chapter), chapter: chapter) }
        if chapter.isVolume && (chapter.url ?? "").hasPrefix(chapter.title ?? "") { return try finish("", chapter: chapter) }
        if (rule.content ?? "").isEmpty { return try finish(chapter.url ?? "", chapter: chapter) }
        let mediaWebView = bookIsMedia(context) && (!(rule.webJs ?? "").isEmpty || !(rule.sourceRegex ?? "").isEmpty)
        if !bookIsMedia(context), !(rule.webJs ?? "").isEmpty || !(rule.sourceRegex ?? "").isEmpty {
            throw WebBookError.unsupported("正文 WebView/webJs/sourceRegex")
        }
        let base = chapter.baseUrl ?? book.tocUrl ?? context.source.bookSourceUrl ?? ""
        func request(_ url: String, baseURL: String) async throws -> AnalyzeUrlExecutor.Response {
            try await context.request(url, baseURL: baseURL, bindings: ["chapter": try WebBookContext.object(chapter)],
                webJs: rule.webJs, sourceRegex: rule.sourceRegex, forceWebView: mediaWebView)
        }
        let firstURL = WebBookContext.absolute(chapter.url ?? "", base: base)
        let first = try await request(firstURL, baseURL: base)
        let parser = try context.parser(first.body, baseURL: firstURL, chapter: chapter, nextChapterURL: nextChapterURL)
        let nextChapter = WebBookContext.absolute(nextChapterURL ?? "", base: first.url)
        var visited: Set<String> = [firstURL, first.url]
        var data = try page(context: context, chapter: chapter, response: first, rule: rule, nextChapterURL: nextChapterURL, baseURL: firstURL)
        var contents = [data.0]
        if data.1.count == 1 {
            while let url = data.1.first, url != nextChapter, visited.insert(url).inserted {
                let response = try await request(url, baseURL: first.url)
                if response.url == nextChapter || (response.url != url && !visited.insert(response.url).inserted) { break }
                let next = try page(context: context, chapter: chapter, response: response, rule: rule, nextChapterURL: nextChapterURL, baseURL: url)
                contents.append(next.0)
                data = next
            }
        } else {
            for url in data.1 where url != nextChapter && visited.insert(url).inserted {
                let response = try await request(url, baseURL: first.url)
                if response.url == nextChapter || (response.url != url && !visited.insert(response.url).inserted) { continue }
                let next = try page(context: context, chapter: chapter, response: response, rule: rule,
                                    getNext: false, nextChapterURL: nextChapterURL, baseURL: url)
                contents.append(next.0)
            }
        }
        var content = contents.joined(separator: "\n")
        if let replacement = rule.replaceRegex, !replacement.isEmpty {
            content = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            content = try parser.getString(replacement, content: content)
        }
        var updated = chapter
        if let titleRule = rule.title, !titleRule.isEmpty {
            let title = try WebBookContext.optional { try parser.getString(titleRule) } ?? ""
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let image = try NSRegularExpression(pattern: #"(.*)((?:data|https?):[\s\S]+)$"#)
                if let match = image.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
                    let name = (title as NSString).substring(with: match.range(at: 1))
                    updated.title = name.isEmpty ? chapter.title : name
                    updated.imgUrl = (title as NSString).substring(with: match.range(at: 2))
                } else { updated.title = title }
            }
        }
        guard chapter.isVolume || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WebBookError.emptyContent }
        try Task.checkCancellation()
        return try finish(content, chapter: updated)
    }

    private static func page(context: WebBookContext, chapter: BookChapter, response: AnalyzeUrlExecutor.Response,
                             rule: ContentRule, getNext: Bool = true, nextChapterURL: String? = nil, baseURL: String) throws -> (String, [String]) {
        try Task.checkCancellation()
        let parser = try context.parser(response.body, baseURL: baseURL, chapter: chapter, nextChapterURL: nextChapterURL)
        let raw = try parser.getString(rule.content, unescape: false)
        let isMediaAddress = context.book?.isAudio == true || context.book?.isVideo == true
        let content = isMediaAddress ? raw : try HTML4Entities.unescape(HtmlFormatter.formatKeepImg(raw, redirectUrl: URL(string: response.url)))
        let next = getNext ? try context.urls(parser, rule: rule.nextContentUrl, base: response.url) : []
        return (content, next)
    }

    private static func bookIsMedia(_ context: WebBookContext) -> Bool {
        context.book?.isAudio == true || context.book?.isVideo == true || context.book?.isImage == true
    }
}
