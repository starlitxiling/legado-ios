import Foundation

final class BatchContentContext {
    private let lock = NSLock()
    private var closed = false
    private var saved = Set<Int>()
    private let chapters: [BookChapter]
    private let context: WebBookContext
    private let book: Book
    private let directory: URL

    init(chapters: [BookChapter], context: WebBookContext, book: Book, directory: URL) throws {
        guard Set(chapters.map(\.index)).count == chapters.count else {
            throw JsEngineError.exception("Batch chapter indexes must be unique")
        }
        self.chapters = chapters; self.context = context; self.book = book; self.directory = directory
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true
    }

    func missingChapters() -> [BookChapter] {
        lock.lock(); defer { lock.unlock() }
        return chapters.filter { !saved.contains($0.index) }
    }

    func saveContent(identifier: Any?, content: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        guard !closed else { return false }
        guard let chapter = resolve(identifier) else {
            throw JsEngineError.exception("java.cacheContent requires a unique batch chapter; use a chapter object for duplicate URLs")
        }
        var text = content
        if let rule = context.source.ruleContent?.replaceRegex, !rule.isEmpty {
            let base = WebBookContext.absolute(chapter.url ?? "", base: chapter.baseUrl ?? book.tocUrl ?? "")
            let parser = try context.parser("", baseURL: base, chapter: chapter)
            text = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
            text = try parser.getString(rule, content: text)
            if book.isOnLineTxt { text = text.components(separatedBy: "\n").map { "\u{3000}\u{3000}" + $0 }.joined(separator: "\n") }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        try BookHelp.save(text, directory: directory, book: book, chapter: chapter)
        saved.insert(chapter.index)
        return true
    }

    private func resolve(_ identifier: Any?) -> BookChapter? {
        if let object = identifier as? [String: Any], let number = integralScriptNumber(object["index"]),
           number >= Double(Int32.min), number <= Double(Int32.max) {
            return chapters.first { $0.index == Int(number) }
        }
        guard let url = identifier as? String, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let base = (book.tocUrl ?? "").isEmpty ? context.source.bookSourceUrl ?? "" : book.tocUrl ?? ""
        let address = WebBookContext.absolute(url, base: base)
        let candidates = chapters.filter {
            $0.url == url.trimmingCharacters(in: .whitespacesAndNewlines)
                || WebBookContext.absolute($0.url ?? "", base: base) == address
                || WebBookContext.absolute($0.url ?? "", base: $0.baseUrl ?? base) == address
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
