import Foundation

public enum BookChapterList {
    public static func load(source: BookSource, book: Book, client: any HttpClient, tocCountWords: Bool = false,
                            runPreUpdate: Bool = false, fromBookInfo: Bool = false) async throws -> [BookChapter] {
        try await load(context: WebBookContext(source: source, client: client, book: book), book: book, tocCountWords: tocCountWords,
            runPreUpdate: runPreUpdate, fromBookInfo: fromBookInfo)
    }

    static func load(context: WebBookContext, book: Book, tocCountWords: Bool = false,
                     runPreUpdate: Bool = false, fromBookInfo: Bool = false) async throws -> [BookChapter] {
        try Task.checkCancellation()
        let rule = context.source.ruleToc ?? TocRule()
        let (listRule, reverse) = WebBookContext.listRule(rule.chapterList)
        guard !listRule.isEmpty else { throw WebBookError.missingRule("chapterList") }
        if runPreUpdate, let script = rule.preUpdateJs, !script.isEmpty {
            let parser = try context.parser("", baseURL: book.tocUrl ?? "", fromBookInfo: fromBookInfo)
            parser.refreshBook = { [weak context] research in
                guard let context else { throw CancellationError() }
                if !research && fromBookInfo { return }
                let original = try context.bookStore.snapshot()
                let updated = try HostAsyncBridge.wait {
                    let web = WebBook(source: context.source, client: context.client, cookies: context.cookies,
                        configuration: context.configuration)
                    var book = original
                    book.infoHtml = nil; book.tocHtml = nil
                    if research {
                        let found = try await web.preciseSearch(name: book.name ?? "", author: book.author ?? "")
                        book.bookUrl = found.bookUrl
                        let variables = try JsBookBinding(book)
                        for (key, value) in try JsBookBinding(found).store.variables { variables.setValue(value, for: key) }
                        book.variable = try variables.snapshot().variable
                    }
                    return try await web.bookInfo(book)
                }
                context.bookStore.book = updated
                context.bookStore.store.replace(with: try JsBookBinding(updated).store.variables)
            }
            _ = try parser.getString("@js:" + script)
        }
        let book = try context.bookStore.snapshot()
        let firstURL = (book.tocUrl ?? "").isEmpty ? book.bookUrl ?? "" : book.tocUrl ?? ""
        let first: AnalyzeUrlExecutor.Response
        if book.bookUrl == firstURL, let body = book.tocHtml, !body.isEmpty, let url = URL(string: firstURL) {
            first = .init(raw: HttpResponse(status: 200, body: Data(body.utf8), finalURL: url), body: body)
        } else { first = try await context.request(firstURL, baseURL: context.source.bookSourceUrl ?? "") }
        var visited: Set<String> = [WebBookContext.absolute(firstURL, base: context.source.bookSourceUrl ?? ""), first.url]
        var data = try page(context: context, book: book, response: first, rule: rule, listRule: listRule,
                            baseURL: firstURL, tocCountWords: tocCountWords)
        var chapters = data.0
        if data.1.count == 1 {
            while let url = data.1.first, visited.insert(url).inserted {
                let response = try await context.request(url, baseURL: first.url)
                if response.url != url && !visited.insert(response.url).inserted { break }
                data = try page(context: context, book: book, response: response, rule: rule, listRule: listRule,
                                baseURL: url, tocCountWords: tocCountWords)
                chapters.append(contentsOf: data.0)
            }
        } else {
            let urls = data.1.filter { visited.insert($0).inserted }
            let pages = try await context.mapPages(urls) { context, url in
                let response = try await context.request(url, baseURL: first.url)
                let chapters = try page(context: context, book: book, response: response,
                    rule: rule, listRule: listRule, getNext: false, baseURL: url, tocCountWords: tocCountWords).0
                return (url, response.url, chapters)
            }
            for (url, redirectedURL, pageChapters) in pages {
                if redirectedURL != url && !visited.insert(redirectedURL).inserted { continue }
                chapters.append(contentsOf: pageChapters)
            }
        }
        guard !chapters.isEmpty else { throw WebBookError.emptyToc }
        if !reverse { chapters.reverse() }
        var seen = Set<String>()
        chapters = chapters.filter { seen.insert($0.url ?? "").inserted }
        if book.readConfig?.reverseToc != true { chapters.reverse() }
        for index in chapters.indices {
            try Task.checkCancellation()
            chapters[index].index = index
        }
        if let script = rule.formatJs, !script.isEmpty {
            let engine = try context.engine(baseURL: first.url)
            let values = try chapters.map(WebBookContext.object)
            let parser = try context.parser("", baseURL: first.url)
            parser.contextBindings["chapters"] = values
            let titles = try engine.evaluateScript("""
                var gInt = 0;
                chapters.map(function(chapter, offset) {
                    var index = offset + 1, title = chapter.title;
                    try { var result = eval(formatScript); return result == null ? title : String(result); }
                    catch (error) { return title; }
                });
                """, bindings: ["formatScript": script], context: parser) as? [String]
            for index in chapters.indices {
                try Task.checkCancellation()
                if let titles, titles.indices.contains(index) { chapters[index].title = titles[index] }
            }
        }
        return chapters
    }

    public static func upChapterInfo(_ chapters: [BookChapter], previous: [BookChapter], enabled: Bool) -> [BookChapter] {
        guard enabled else { return chapters }
        let previous = Dictionary(previous.map { ("\($0.index)_\($0.title ?? "")", $0) }, uniquingKeysWith: { _, last in last })
        return chapters.map { chapter in
            guard let old = previous["\(chapter.index)_\(chapter.title ?? "")"] else { return chapter }
            var result = chapter
            if let value = old.wordCount { result.wordCount = value }
            if let value = old.variable { result.variable = value }
            if let value = old.imgUrl { result.imgUrl = value }
            return result
        }
    }

    private static func page(context: WebBookContext, book: Book, response: AnalyzeUrlExecutor.Response,
                             rule: TocRule, listRule: String, getNext: Bool = true, baseURL: String,
                             tocCountWords: Bool) throws -> ([BookChapter], [String]) {
        return try autoreleasepool {
            let parser = try context.parser(response.body, baseURL: baseURL)
            let elements = try parser.getElements(listRule)
            let next = getNext ? try context.urls(parser, rule: rule.nextTocUrl, base: response.url) : []
            var chapters: [BookChapter] = []
            for (index, element) in elements.enumerated() {
                try autoreleasepool {
                    try Task.checkCancellation()
                    var chapter = BookChapter()
                    chapter.baseUrl = response.url; chapter.bookUrl = book.bookUrl
                    let binding = try JsChapterBinding(chapter)
                    let itemParser = try context.parser(element, baseURL: baseURL, chapterBinding: binding)
                    func value(_ rule: String?) throws -> String {
                        binding.chapter = chapter
                        return try itemParser.getString(rule)
                    }
                    chapter.title = try value(rule.chapterName)
                    guard !(chapter.title ?? "").isEmpty else { return }
                    chapter.url = try value(rule.chapterUrl)
                    let info = try value(rule.updateTime)
                    chapter.isVolume = WebBookContext.flag(try value(rule.isVolume))
                    chapter.tag = info
                    if tocCountWords && !chapter.isVolume {
                        let regex = try NSRegularExpression(pattern: #"(?:^|字数[：:、]?|[ \t\n\x{0B}\f\r]+)([0-9万千百\.]{1,6}字)"#)
                        if let match = regex.firstMatch(in: info, range: NSRange(info.startIndex..., in: info)) {
                            chapter.wordCount = (info as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                            chapter.tag = (info as NSString).replacingCharacters(in: match.range, with: "")
                        }
                    }
                    if (chapter.url ?? "").isEmpty {
                        chapter.url = chapter.isVolume ? (chapter.title ?? "") + String(index) : baseURL
                    }
                    chapter.isVip = WebBookContext.flag(try value(rule.isVip))
                    chapter.isPay = WebBookContext.flag(try value(rule.isPay))
                    chapter.variable = try binding.snapshot().variable
                    chapters.append(chapter)
                }
            }
            return (chapters, next)
        }
    }
}
