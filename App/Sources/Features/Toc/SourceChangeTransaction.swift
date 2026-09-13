import LegadoCore

enum SourceChangeTransaction {
    static func save(book: Book, previous: Book, chapters: [BookChapterRow], database: AppDatabase) async throws -> Book {
        let incoming = try DiscoveryStorage.row(book, defaults: BookRow())
        let prior = try DiscoveryStorage.row(previous, defaults: BookRow())
        let saved = try await database.write { db in
            let old = try BookRow.matching(bookUrl: incoming.bookUrl, name: incoming.name, author: incoming.author, in: db)
            var row = incoming
            if let old {
                row = DiscoveryStorage.preservingReading(old, in: row)
            } else {
                row = DiscoveryStorage.preservingReading(prior, in: row)
                row.type |= DiscoveryStorage.hiddenBook
            }
            let progress = old ?? prior
            row.durChapterIndex = ChapterLocator.locate(oldIndex: progress.durChapterIndex,
                oldTitle: progress.durChapterTitle, oldCount: progress.totalChapterNum, titles: chapters.map(\.title))
            if chapters.indices.contains(row.durChapterIndex) {
                row.durChapterTitle = chapters[row.durChapterIndex].title
            }
            if old?.bookUrl != incoming.bookUrl {
                try row.replaceByIdentity(in: db)
            } else {
                try row.save(in: db)
            }
            try BookChapterRow.replaceAll(bookUrl: row.bookUrl, chapters: chapters, in: db)
            try row.updateProgress(in: db)
            return row
        }
        return try DiscoveryStorage.book(saved)
    }
}
