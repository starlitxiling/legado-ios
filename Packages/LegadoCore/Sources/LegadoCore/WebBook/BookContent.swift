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
                            includeTitle: Bool = true, configuration: WebBookConfiguration = .init()) async throws -> Result {
        try await cached(source: source, book: book, chapter: chapter, client: client, cookies: CookieStore(),
            configuration: configuration, processor: processor, includeTitle: includeTitle) {
                try await load(context: WebBookContext(source: source, client: client, book: book, configuration: configuration),
                    book: book, chapter: chapter, nextChapterURL: nextChapterURL, processor: processor, includeTitle: includeTitle)
            }
    }

    static func cached(source: BookSource, book: Book, chapter: BookChapter, client: any HttpClient,
                       cookies: CookieStore, configuration: WebBookConfiguration, processor: ContentProcessor,
                       includeTitle: Bool, load: () async throws -> Result) async throws -> Result {
        try Task.checkCancellation()
        guard let directory = configuration.cacheDirectory, !LocalBook.isLocal(book) else {
            return try await load()
        }
        let result: Result
        if let text = try BookHelp.content(directory: directory, book: book, chapter: chapter) {
            let processed = try processor.getContent(book: book, chapter: chapter, content: text, includeTitle: includeTitle)
            result = Result(chapter: chapter, rawContent: text, text: processed.text, paragraphs: processed.paragraphs,
                imageStyle: book.readConfig?.imageStyle ?? source.ruleContent?.imageStyle ?? (source.bookSourceType == 2 ? "FULL" : nil),
                payAction: source.ruleContent?.payAction)
        } else {
            result = try await load()
            try Task.checkCancellation()
            try BookHelp.save(result.rawContent, directory: directory, book: book, chapter: chapter)
        }
        try await BookHelp.saveImages(source: source, book: book, chapter: result.chapter, content: result.rawContent,
            directory: directory, client: client, cookies: cookies)
        try Task.checkCancellation()
        guard let saved = try BookHelp.content(directory: directory, book: book, chapter: chapter) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey:
                BookHelp.contentURL(directory: directory, book: book, chapter: chapter).path])
        }
        return Result(chapter: result.chapter, rawContent: saved, text: result.text, paragraphs: result.paragraphs,
            imageStyle: result.imageStyle, payAction: result.payAction)
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
        let base = chapter.baseUrl ?? book.tocUrl ?? context.source.bookSourceUrl ?? ""
        func request(_ url: String, baseURL: String) async throws -> AnalyzeUrlExecutor.Response {
            try await context.request(url, baseURL: baseURL, chapter: chapter,
                webJs: rule.webJs, sourceRegex: rule.sourceRegex)
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
            let urls = data.1.filter { $0 != nextChapter && visited.insert($0).inserted }
            let pages = try await context.mapPages(urls, chapter: chapter) { context, url in
                let response = try await context.request(url, baseURL: first.url, chapter: chapter,
                    webJs: rule.webJs, sourceRegex: rule.sourceRegex)
                let content = try page(context: context, chapter: chapter, response: response, rule: rule,
                    getNext: false, nextChapterURL: nextChapterURL, baseURL: url).0
                return (url, response.url, content)
            }
            for (url, redirectedURL, content) in pages {
                if redirectedURL == nextChapter || (redirectedURL != url && !visited.insert(redirectedURL).inserted) { continue }
                contents.append(content)
            }
        }
        if let subRule = rule.subContent, !subRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let raw = try parser.getString(subRule)
            if book.isOnLineTxt { contents.append(raw) }
            else {
                do {
                    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.lowercased().hasPrefix("http") {
                        text = try await context.request(text, baseURL: first.url, chapter: chapter).body
                    }
                    if book.isAudio { try context.chapterBinding(chapter).setValue(text, for: "lyric") }
                    else if book.isVideo { try context.chapterBinding(chapter).setValue(text, for: "danmaku") }
                } catch {
                    try Task.checkCancellation()
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                    NSLog("Sub-content failed for %@: %@", chapter.url ?? "", String(describing: error))
                }
            }
        }
        var content = contents.joined(separator: "\n")
        if let replacement = rule.replaceRegex, !replacement.isEmpty {
            content = content.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            content = try parser.getString(replacement, content: content)
            if book.isOnLineTxt {
                content = content.components(separatedBy: "\n").map { "\u{3000}\u{3000}" + $0 }.joined(separator: "\n")
            }
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
        updated.variable = try context.chapterBinding(chapter).snapshot().variable
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
        let protected = try ProtectedHTML(raw, enabled: context.configuration.adaptSpecialStyle && !isMediaAddress)
        let content = isMediaAddress ? raw : try protected.restore(HTML4Entities.unescape(
            HtmlFormatter.formatKeepImg(protected.text, redirectUrl: URL(string: response.url))))
        let next = getNext ? try context.urls(parser, rule: rule.nextContentUrl, base: response.url) : []
        return (content, next)
    }

}
