import Foundation
import LegadoCore

struct ReaderLayoutInput {
    var book: Book
    let chapter: BookChapter
    var rawContent: String
    var rules: [ReplaceRuleRow]
    var highlightRules: [HighlightRule] = []
    var sourceImageStyle: String?
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
        let imageStyle = [input.book.readConfig?.imageStyle, input.sourceImageStyle].compactMap { $0 }.first { !$0.isEmpty }
            ?? (input.book.isImage || LocalBook.fileURL(input.book)?.pathExtension.lowercased() == "pdf" ? "FULL" : "DEFAULT")
        var settings = settings
        settings.pageAnim = input.book.readConfig?.pageAnim ?? settings.pageAnim
        let pagination = try Paginator().paginate(title: title, paragraphs: content.paragraphs,
            size: size, settings: settings, imageBaseURL: LocalBook.isLocal(input.book) ? "legado-local://book/" : URL(string: input.chapter.url ?? "",
                relativeTo: URL(string: input.chapter.baseUrl ?? input.book.bookUrl ?? ""))?.absoluteURL.absoluteString, isVolume: input.chapter.isVolume, highlightRules: input.highlightRules, book: input.book, imageStyle: imageStyle, imageSize: { url in
                do {
                    let data: Data?
                    if LocalBook.isLocal(input.book) { data = try LocalBook.image(book: input.book, href: CustomUrl(url).getUrl()) }
                    else if let directory = input.cacheDirectory { data = try BookHelp.imageData(directory: directory, book: input.book, src: url) }
                    else { data = nil }
                    return data.flatMap(ReaderImageLayout.naturalSize)
                } catch is CancellationError { throw CancellationError() }
                catch { NSLog("Unable to read image dimensions for %@: %@", url, error.localizedDescription); return nil }
            })
        return ReaderLayoutResult(title: title, pagination: pagination)
    }
}
