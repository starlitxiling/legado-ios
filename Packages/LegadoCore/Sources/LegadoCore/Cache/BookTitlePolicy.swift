import Foundation

extension Book {
    public func useReplaceRule(defaultEnabled: Bool = true) -> Bool {
        if let enabled = readConfig?.useReplaceRule { return enabled }
        let localEpub = LocalBook.isLocal(self) && (LocalBook.fileURL(self)?.pathExtension.lowercased() == "epub"
            || URL(string: bookUrl ?? "")?.pathExtension.lowercased() == "epub")
        return !isImage && !localEpub && defaultEnabled
    }
}

extension BookHelp {
    private static func titleMarkerURL(directory: URL, book: Book, chapter: BookChapter) -> URL {
        contentURL(directory: directory, book: book, chapter: chapter).deletingPathExtension().appendingPathExtension("nr")
    }

    public static func removeSameTitle(directory: URL, book: Book, chapter: BookChapter) -> Bool {
        !FileManager.default.fileExists(atPath: titleMarkerURL(directory: directory, book: book, chapter: chapter).path)
    }

    public static func setRemoveSameTitle(_ enabled: Bool, directory: URL, book: Book, chapter: BookChapter) throws {
        let url = titleMarkerURL(directory: directory, book: book, chapter: chapter)
        if enabled {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url, options: .atomic)
        }
    }
}
