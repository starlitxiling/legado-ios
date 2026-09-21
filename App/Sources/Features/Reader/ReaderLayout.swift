import Foundation
import LegadoCore

struct ReaderLayoutInput {
    var book: Book
    let chapter: BookChapter
    var rawContent: String
    var rules: [ReplaceRuleRow]
    var highlightRules: [HighlightRule] = []
    var manualReplace = false
    var replaceEnableDefault = true
    var chineseConverterType = 0
    var adaptSpecialStyle = true
    var cacheDirectory: URL?
}

struct ReaderLayoutResult {
    let title: String
    let pagination: ReaderPagination
}

enum ReaderLayout {
    private static let processors = ContentProcessorPool()
    static func build(input: ReaderLayoutInput, size: CGSize, settings: ReaderSettings,
                      didStart: @Sendable () -> Void) throws -> ReaderLayoutResult {
        try Task.checkCancellation()
        didStart()
        let rules = try input.rules.map { try ReaderEntityBridge.decode(ReplaceRule.self, row: $0) }
        let processor = processors.get(book: input.book, rules: rules, configuration: .init(paragraphIndent: settings.paragraphIndent, chineseConverterType: input.chineseConverterType,
            replaceEnableDefault: input.replaceEnableDefault, adaptSpecialStyle: input.adaptSpecialStyle, cacheDirectory: input.cacheDirectory, manualReplace: input.manualReplace))
        let title = try processor.title(book: input.book, chapter: input.chapter)
        let content = try processor.getContent(book: input.book, chapter: input.chapter,
            content: input.rawContent, includeTitle: false)
        let pagination = try Paginator().paginate(title: title, paragraphs: content.paragraphs,
            size: size, settings: settings, imageBaseURL: LocalBook.isLocal(input.book) ? "legado-local://book/" : URL(string: input.chapter.url ?? "",
                relativeTo: URL(string: input.chapter.baseUrl ?? input.book.bookUrl ?? ""))?.absoluteURL.absoluteString, isVolume: input.chapter.isVolume, highlightRules: input.highlightRules, book: input.book)
        return ReaderLayoutResult(title: title, pagination: pagination)
    }
}
