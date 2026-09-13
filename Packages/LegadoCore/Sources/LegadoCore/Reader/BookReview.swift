import Foundation

public final class BookReview {
    private let source: BookSource
    private let client: any HttpClient

    public init(source: BookSource, client: any HttpClient) {
        self.source = source
        self.client = (client as? any SourceSessionClientProviding)?.client(for: source) ?? client
    }

    public func details(book: Book, chapter: BookChapter, paragraphIndex: Int,
                        paragraphData: String = "", page: Int = 1) async throws -> [ReaderReviewItem] {
        guard let rule = source.ruleReview, rule.enabled,
              let url = rule.reviewDetailUrl, !url.isEmpty else { return [] }
        let context = WebBookContext(source: source, client: client, book: book)
        let base = chapter.url ?? book.bookUrl ?? source.bookSourceUrl ?? ""
        let response = try await context.request(url, baseURL: base,
            bindings: ["chapter": try WebBookContext.object(chapter), "paraIndex": String(paragraphIndex),
                       "paraData": paragraphData, "page": page])
        let parser = try context.parser(response.body, baseURL: response.url, chapter: chapter)
        parser.setLocal("paraIndex", value: String(paragraphIndex))
        parser.setLocal("paraData", value: paragraphData)
        parser.setLocal("page", value: String(page))
        return try ReaderReviewEvaluator.details(body: response.body, rule: rule, parser: parser)
    }

    public func summary(book: Book, chapter: BookChapter) async throws -> ReaderReviewSummary {
        guard let rule = source.ruleReview, rule.enabled,
              let url = rule.reviewSummaryUrl, !url.isEmpty else { return ReaderReviewSummary() }
        let context = WebBookContext(source: source, client: client, book: book)
        let response = try await context.request(url, baseURL: chapter.url ?? book.bookUrl ?? "",
            bindings: ["chapter": try WebBookContext.object(chapter)])
        return try ReaderReviewEvaluator.summary(body: response.body, rule: rule,
            parser: context.parser(response.body, baseURL: response.url, chapter: chapter))
    }
}
