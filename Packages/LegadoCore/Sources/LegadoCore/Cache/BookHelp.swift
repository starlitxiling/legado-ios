import Foundation
import CryptoKit

public enum BookHelp {
    static func md5(_ value: String) -> String {
        String(Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().dropFirst(8).prefix(16))
    }

    public static func chapterFileName(_ chapter: BookChapter) -> String {
        String(format: "%05d", locale: Locale(identifier: "en_US_POSIX"), chapter.index)
            + "-" + md5(chapter.title ?? "") + ".nb"
    }

    public static func folderName(_ book: Book) -> String {
        let name = (book.name ?? "").replacingOccurrences(of: #"[\\/:*?"<>|.]"#, with: "", options: .regularExpression)
        return String(decoding: name.utf16.prefix(9), as: UTF16.self) + md5(book.bookUrl ?? "")
    }

    public static func contentURL(directory: URL, book: Book, chapter: BookChapter) -> URL {
        directory.appendingPathComponent("book_cache", isDirectory: true)
            .appendingPathComponent(folderName(book), isDirectory: true).appendingPathComponent(chapterFileName(chapter))
    }

    public static func content(directory: URL, book: Book, chapter: BookChapter) throws -> String? {
        let url = contentURL(directory: directory, book: book, chapter: chapter)
        if FileManager.default.fileExists(atPath: url.path) { return try String(contentsOf: url, encoding: .utf8) }
        let root = directory.appendingPathComponent("book_cache", isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            let suffix = md5(book.bookUrl ?? "")
            let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(suffix) }.sorted { $0.path < $1.path }
            for folder in folders {
                let cached = folder.appendingPathComponent(chapterFileName(chapter))
                if FileManager.default.fileExists(atPath: cached.path) { return try String(contentsOf: cached, encoding: .utf8) }
            }
        }
        struct Cached: Decodable { let rawContent: String }
        let legacy = try ReaderCacheStatus.fileURL(book: book, chapter: chapter, directory: directory)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return nil }
        return try JSONDecoder().decode(Cached.self, from: Data(contentsOf: legacy)).rawContent
    }

    public static func hasContent(directory: URL, book: Book, chapter: BookChapter) -> Bool {
        (chapter.isVolume && (chapter.url ?? "").hasPrefix(chapter.title ?? ""))
            || (try? content(directory: directory, book: book, chapter: chapter)) != nil
    }

    public static func save(_ content: String, directory: URL, book: Book, chapter: BookChapter) throws {
        try Task.checkCancellation()
        let url = contentURL(directory: directory, book: book, chapter: chapter)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func formatChapterName(book: Book, chapter: BookChapter, rules: [ReplaceRule] = [],
                                         useReplace: Bool = true) throws -> String {
        try ContentProcessor(rules: rules).title(book: book, chapter: chapter, useReplace: useReplace)
    }
}
