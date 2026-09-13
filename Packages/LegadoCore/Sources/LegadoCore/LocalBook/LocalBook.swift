import Foundation
import GRDB

public enum LocalBook {
    public static func isLocal(_ book: Book) -> Bool {
        book.origin == "loc_book" && URL(string: book.bookUrl ?? "")?.isFileURL == true
    }

    public static func nameAuthor(_ filename: String) -> (name: String, author: String) {
        let stem = (filename as NSString).deletingPathExtension
        let patterns = ["(.*?)《([^《》]+)》.*?作者：(.*)", "(.*?)《([^《》]+)》(.*)", "(^)(.+) 作者：(.+)$", "(^)(.+) by (.+)$"]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) else { continue }
            let value = stem as NSString
            return (value.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines),
                    WebBookContext.name(value.substring(with: match.range(at: 1)) + value.substring(with: match.range(at: 3)), author: true))
        }
        let name = WebBookContext.name(stem)
        let remainder = stem.replacingOccurrences(of: name, with: "")
        let author = WebBookContext.name(remainder, author: true)
        return (name, author.count == stem.count ? "" : author)
    }

    public static func parse(url: URL, rules: [TxtTocRule] = TxtTocRule.builtIn) throws -> (book: Book, chapters: [BookChapter], cover: Data?) {
        guard url.isFileURL, ["txt", "epub"].contains(url.pathExtension.lowercased()) else { throw LocalBookError.unsupportedFile }
        var book = Book()
        let identity = nameAuthor(url.lastPathComponent)
        book.name = identity.name; book.author = identity.author
        book.bookUrl = url.absoluteString; book.origin = "loc_book"; book.originName = url.lastPathComponent
        book.type = 256 | 8; book.canUpdate = false
        let chapters: [BookChapter]
        let cover: Data?
        if url.pathExtension.lowercased() == "epub" {
            let parser = try EpubParserCache.shared.parser(for: url)
            chapters = try parser.chapters(bookURL: url.absoluteString)
            cover = parser.cover
            if !parser.title.isEmpty { book.name = parser.title }
            if !parser.author.isEmpty { book.author = parser.author }
        } else {
            let parser = try TextFileParser(url: url)
            book.charset = parser.charset
            chapters = try parser.chapters(bookURL: url.absoluteString, rules: rules)
            cover = nil
        }
        book.totalChapterNum = chapters.count; book.latestChapterTitle = chapters.last?.title
        book.durChapterTitle = chapters.first?.title
        return (book, chapters, cover)
    }

    public static func chapterList(book: Book, rules: [TxtTocRule] = TxtTocRule.builtIn) throws -> [BookChapter] {
        guard isLocal(book), let url = URL(string: book.bookUrl ?? "") else { throw LocalBookError.unsupportedFile }
        switch url.pathExtension.lowercased() {
        case "txt": return try TextFileParser(url: url).chapters(bookURL: url.absoluteString, rules: rules)
        case "epub": return try EpubParserCache.shared.parser(for: url).chapters(bookURL: url.absoluteString)
        default: throw LocalBookError.unsupportedFile
        }
    }

    public static func content(book: Book, chapter: BookChapter) throws -> String {
        guard isLocal(book), let url = URL(string: book.bookUrl ?? "") else { throw LocalBookError.unsupportedFile }
        switch url.pathExtension.lowercased() {
        case "txt": return try TextFileParser(url: url).content(chapter: chapter)
        case "epub": return try EpubParserCache.shared.parser(for: url).content(chapter: chapter)
        default: throw LocalBookError.unsupportedFile
        }
    }

    @discardableResult
    public static func save(book: Book, chapters: [BookChapter], database: AppDatabase,
                            keepBoth: Bool = false) async throws -> BookRow {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        let row = try decoder.decode(BookRow.self, from: encoder.encode(book))
        let rows = try chapters.map { try decoder.decode(BookChapterRow.self, from: encoder.encode($0)) }
        guard rows.allSatisfy({ $0.bookUrl == row.bookUrl }) else { throw StorageError.chapterBookMismatch }
        return try await database.write { db in
            var saved = row
            if let existing = try BookRow.fetchOne(db, key: row.bookUrl) {
                saved = existing
                saved.name = row.name; saved.author = row.author; saved.coverUrl = row.coverUrl
                saved.originName = row.originName; saved.charset = row.charset
                saved.totalChapterNum = row.totalChapterNum; saved.latestChapterTitle = row.latestChapterTitle
                saved.latestChapterTime = 0
                try saved.update(db)
                try db.execute(sql: "DELETE FROM chapters WHERE bookUrl = ?", arguments: [saved.bookUrl])
            } else {
                let name = saved.name
                var suffix = 2
                while try BookRow.fetchOne(db, sql: "SELECT * FROM books WHERE name = ? AND author = ?",
                                           arguments: [saved.name, saved.author]) != nil {
                    guard keepBoth else { throw LocalBookError.identityConflict(saved.name, saved.author) }
                    saved.name = "\(name) (\(suffix))"; suffix += 1
                }
                try saved.insert(db)
            }
            let revision = UUID().uuidString
            for var chapter in rows {
                var variables = try chapter.variable.map { try JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
                variables["localImportRevision"] = revision
                chapter.variable = String(decoding: try JSONEncoder().encode(variables), as: UTF8.self)
                try chapter.insert(db)
            }
            return saved
        }
    }
}
