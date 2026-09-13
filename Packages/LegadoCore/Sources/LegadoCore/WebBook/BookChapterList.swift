import Foundation

public enum BookChapterList {
    public static func load(source: BookSource, book: Book, client: any HttpClient, tocCountWords: Bool = false) async throws -> [BookChapter] {
        try await load(context: WebBookContext(source: source, client: client, book: book), book: book, tocCountWords: tocCountWords)
    }

    static func load(context: WebBookContext, book: Book, tocCountWords: Bool = false) async throws -> [BookChapter] {
        try Task.checkCancellation()
        let rule = context.source.ruleToc ?? TocRule()
        let (listRule, reverse) = WebBookContext.listRule(rule.chapterList)
        guard !listRule.isEmpty else { throw WebBookError.missingRule("chapterList") }
        if let script = rule.preUpdateJs, !script.isEmpty {
            _ = try context.engine(baseURL: book.tocUrl ?? "").evaluateScript(script,
                bindings: ["book": ["name": book.name ?? "", "bookUrl": book.bookUrl ?? ""]])
        }
        let firstURL = (book.tocUrl ?? "").isEmpty ? book.bookUrl ?? "" : book.tocUrl ?? ""
        let first = try await context.request(firstURL, baseURL: context.source.bookSourceUrl ?? "")
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
            // 多链接是本次目录的完整分页清单，不递归展开子页的下一页规则。
            for url in data.1 where visited.insert(url).inserted {
                let response = try await context.request(url, baseURL: first.url)
                if response.url != url && !visited.insert(response.url).inserted { continue }
                chapters.append(contentsOf: try page(context: context, book: book, response: response,
                    rule: rule, listRule: listRule, getNext: false, baseURL: url, tocCountWords: tocCountWords).0)
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
            let titles = try engine.evaluateScript("""
                var gInt = 0;
                chapters.map(function(chapter, offset) {
                    var index = offset + 1, title = chapter.title;
                    try { var result = eval(formatScript); return result == null ? title : String(result); }
                    catch (error) { return title; }
                });
                """, bindings: ["chapters": values, "formatScript": script]) as? [String]
            for index in chapters.indices {
                try Task.checkCancellation()
                if let titles, titles.indices.contains(index) { chapters[index].title = titles[index] }
            }
        }
        return chapters
    }

    private static func page(context: WebBookContext, book: Book, response: AnalyzeUrlExecutor.Response,
                             rule: TocRule, listRule: String, getNext: Bool = true, baseURL: String,
                             tocCountWords: Bool) throws -> ([BookChapter], [String]) {
        let parser = try context.parser(response.body, baseURL: baseURL)
        let elements = try parser.getElements(listRule)
        let next = getNext ? try context.urls(parser, rule: rule.nextTocUrl, base: response.url) : []
        var chapters: [BookChapter] = []
        for (index, element) in elements.enumerated() {
            try Task.checkCancellation()
            var chapter = BookChapter()
            chapter.baseUrl = response.url; chapter.bookUrl = book.bookUrl
            func value(_ rule: String?) throws -> String {
                try context.parser(element, baseURL: baseURL, chapter: chapter).getString(rule)
            }
            chapter.title = try value(rule.chapterName)
            guard !(chapter.title ?? "").isEmpty else { continue }
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
            chapters.append(chapter)
        }
        return (chapters, next)
    }
}
