import Foundation
import LegadoCore

struct ReaderLayoutInput {
    let book: Book
    let chapter: BookChapter
    let rawContent: String
    let rules: [ReplaceRuleRow]
}

struct ReaderLayoutResult {
    let title: String
    let pagination: ReaderPagination
}

enum ReaderLayout {
    static func build(input: ReaderLayoutInput, size: CGSize, settings: ReaderSettings,
                      didStart: @Sendable () -> Void) throws -> ReaderLayoutResult {
        try Task.checkCancellation()
        didStart()
        let rules = try input.rules.map { try ReaderEntityBridge.decode(ReplaceRule.self, row: $0) }
        let processor = ContentProcessor(rules: rules, paragraphIndent: settings.paragraphIndent)
        let title = try processor.title(book: input.book, chapter: input.chapter)
        let content = try processor.getContent(book: input.book, chapter: input.chapter,
            content: input.rawContent, includeTitle: false)
        let pagination = try Paginator().paginate(title: title, paragraphs: content.paragraphs,
            size: size, settings: settings, imageBaseURL: URL(string: input.chapter.url ?? "",
                relativeTo: URL(string: input.chapter.baseUrl ?? input.book.bookUrl ?? ""))?.absoluteURL.absoluteString)
        return ReaderLayoutResult(title: title, pagination: pagination)
    }
}
