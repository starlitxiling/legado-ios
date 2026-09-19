import Foundation

public enum BookList {
    public typealias Filter = (String, String, String?) -> Bool

    public static func analyze(source: BookSource, body: String, baseURL: String,
                               isSearch: Bool = true, filter: Filter? = nil, shouldBreak: ((Int) -> Bool)? = nil) async throws -> [SearchBook] {
        try await analyze(context: WebBookContext(source: source, client: ReplayHttpClient()),
                          body: body, baseURL: baseURL, isSearch: isSearch, filter: filter, shouldBreak: shouldBreak)
    }

    static func analyze(context: WebBookContext, body: String, baseURL: String,
                        requestURL: String? = nil, ruleURL: String? = nil, isRedirected: Bool = false,
                        isSearch: Bool = true, filter: Filter? = nil, shouldBreak: ((Int) -> Bool)? = nil) async throws -> [SearchBook] {
        try Task.checkCancellation()
        let source = context.source
        var rule = source.ruleSearch ?? SearchRule()
        if !isSearch, let explore = source.ruleExplore, !(explore.bookList ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rule = try JSONDecoder().decode(SearchRule.self, from: JSONEncoder().encode(explore))
        }
        let parser = try context.parser(body, baseURL: baseURL)
        let (listRule, reverse) = WebBookContext.listRule(rule.bookList)
        var isInfo = false
        if isSearch, let pattern = source.bookUrlPattern, !pattern.isEmpty {
            let regex = try NSRegularExpression(pattern: pattern)
            isInfo = regex.firstMatch(in: baseURL, range: NSRange(baseURL.startIndex..., in: baseURL))?.range == NSRange(baseURL.startIndex..., in: baseURL)
        }
        let elements = isInfo ? [] : try parser.getElements(listRule)
        if isInfo || (elements.isEmpty && (source.bookUrlPattern ?? "").isEmpty) {
            var book = Book(now: 0)
            if !isRedirected, let requestURL, let ruleURL {
                book.bookUrl = WebBookContext.absolute(ruleURL, base: requestURL)
            } else { book.bookUrl = baseURL }
            book = try await BookInfo.analyze(context: context, book: book, body: body, baseURL: baseURL)
            guard let name = book.name, !name.isEmpty, filter?(name, book.author ?? "", book.kind) ?? true else { return [] }
            var result = SearchBook(now: 0)
            result.bookUrl = book.bookUrl; result.tocUrl = book.tocUrl
            result.name = name; result.author = book.author; result.kind = book.kind
            result.coverUrl = book.coverUrl; result.intro = book.intro; result.wordCount = book.wordCount
            result.latestChapterTitle = book.latestChapterTitle; result.variable = book.variable
            result.infoHtml = body; result.tocHtml = book.tocHtml
            result.origin = source.bookSourceUrl; result.originName = source.bookSourceName
            result.originOrder = source.customOrder
            result.type = context.bookType
            return [result]
        }
        var results: [SearchBook] = []
        var seen = Set<String>()
        let listVariables = context.bookStore.store.variables
        var parsedCount = 0
        for (index, element) in elements.enumerated() {
            if index > 0, shouldBreak?(parsedCount) == true { break }
            try Task.checkCancellation()
            try parser.setContent(element)
            let binding = try JsBookBinding(Book(now: 0))
            binding.store.replace(with: listVariables)
            parser.book = binding
            var book = SearchBook(now: 0)
            book.name = WebBookContext.name(try parser.getString(rule.name))
            guard let name = book.name, !name.isEmpty else { continue }
            binding.name = name
            book.author = WebBookContext.name(try parser.getString(rule.author), author: true)
            binding.book.author = book.author
            book.kind = try WebBookContext.optional { try parser.getStringList(rule.kind)?.joined(separator: ",") } ?? nil
            binding.book.kind = book.kind
            guard filter?(name, book.author ?? "", book.kind) ?? true else { continue }
            let url = try WebBookContext.url(parser, rule: rule.bookUrl, base: baseURL)
            book.bookUrl = url.isEmpty ? baseURL : url
            binding.book.bookUrl = book.bookUrl
            book.origin = source.bookSourceUrl; book.originName = source.bookSourceName
            book.originOrder = source.customOrder
            book.type = context.bookType
            binding.book.origin = book.origin; binding.book.originName = book.originName
            binding.book.originOrder = book.originOrder; binding.book.type = book.type
            let cover = try WebBookContext.optional { WebBookContext.absolute(try parser.getString(rule.coverUrl), base: baseURL) } ?? ""
            if !cover.isEmpty { book.coverUrl = cover }
            binding.book.coverUrl = book.coverUrl
            book.intro = try WebBookContext.optional { HtmlFormatter.formatIntro(try parser.getString(rule.intro)) }
            binding.book.intro = book.intro
            book.wordCount = try WebBookContext.optional { WebBookContext.wordCount(try parser.getString(rule.wordCount)) }
            binding.book.wordCount = book.wordCount
            book.latestChapterTitle = try WebBookContext.optional { try parser.getString(rule.lastChapter) }
            book.variable = try binding.snapshot().variable
            if book.bookUrl == baseURL { book.infoHtml = body }
            parsedCount += 1
            if seen.insert(book.bookUrl ?? "").inserted { results.append(book) }
        }
        return reverse ? Array(results.reversed()) : results
    }
}
