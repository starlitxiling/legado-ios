import Foundation
import LegadoCore

struct ReaderRecoveredSource {
    let book: Book
    let chapters: [BookChapter]
    let index: Int
}

enum ReaderSourceRecovery {
    static func find(book: Book, chapterIndex: Int, chapterTitle: String, sources: [BookSource],
                     client: any HttpClient, configuration: WebBookConfiguration) async throws -> ReaderRecoveredSource {
        var failures: [String] = []
        let result = await withTaskGroup(of: (ReaderRecoveredSource?, String?).self, returning: ReaderRecoveredSource?.self) { group in
            var remaining = sources.makeIterator()
            func submit(_ source: BookSource) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let web = WebBook(source: source, client: client, configuration: configuration)
                        var candidate = try await web.preciseSearch(name: book.name ?? "", author: book.author ?? "")
                        if candidate.tocUrl?.isEmpty != false { candidate = try await web.bookInfo(candidate) }
                        let chapters = try await web.chapterList(book: &candidate)
                        guard !chapters.isEmpty else { throw WebBookError.emptyToc }
                        let position = ChapterLocator.locate(oldIndex: chapterIndex, oldTitle: chapterTitle,
                            oldCount: book.totalChapterNum, titles: chapters.map { $0.title ?? "" })
                        let chapter = chapters[min(max(0, position), chapters.count - 1)]
                        let next = chapters.dropFirst(position + 1).first?.url
                        _ = try await web.content(book: candidate, chapter: chapter, nextChapterUrl: next)
                        try Task.checkCancellation()
                        return (ReaderRecoveredSource(book: candidate, chapters: chapters, index: chapter.index), nil)
                    } catch is CancellationError { return (nil, nil) }
                    catch { return (nil, (source.bookSourceName ?? source.bookSourceUrl ?? "Source") + ": " + error.localizedDescription) }
                }
            }
            for _ in 0..<min(max(1, configuration.threadCount), sources.count) {
                if let source = remaining.next() { submit(source) }
            }
            while let (candidate, error) = await group.next() {
                if let candidate { group.cancelAll(); return candidate }
                if let error { failures.append(error) }
                if Task.isCancelled { group.cancelAll(); break }
                if let source = remaining.next() { submit(source) }
            }
            return nil as ReaderRecoveredSource?
        }
        try Task.checkCancellation()
        guard let result else {
            throw NSError(domain: "ReaderSourceRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "没有可用的替代书源。" + (failures.isEmpty ? "" : "\n" + failures.prefix(5).joined(separator: "\n"))])
        }
        return result
    }
}
