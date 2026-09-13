import Foundation
import CryptoKit

public enum ReaderCacheStatus {
    public static func hasContent(isLocalTXT: Bool, isVolume: Bool, chapterURL: String, title: String, cached: Bool) -> Bool {
        isLocalTXT || (isVolume && chapterURL.hasPrefix(title)) || cached
    }

    public static func fileURL(book: Book, chapter: BookChapter, directory: URL) throws -> URL {
        var identity = [book.bookUrl ?? "", book.origin ?? "", chapter.url ?? "", String(chapter.index)]
        if LocalBook.isLocal(book) { identity.append(chapter.variable ?? "") }
        let key = SHA256.hash(data: try JSONEncoder().encode(identity)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    public static func hasContent(book: Book, chapter: BookChapter, directory: URL) -> Bool {
        struct Cached: Decodable { let rawContent: String }
        let cached = (try? fileURL(book: book, chapter: chapter, directory: directory)).flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Cached.self, from: $0) } != nil
        return hasContent(isLocalTXT: LocalBook.isLocal(book) && URL(string: book.bookUrl ?? "")?.pathExtension.lowercased() == "txt",
            isVolume: chapter.isVolume, chapterURL: chapter.url ?? "", title: chapter.title ?? "", cached: cached)
    }
}
