import Foundation
import GRDB

public enum BuiltinBookGroup: Int64, CaseIterable, Sendable {
    case root = -100, all = -1, local = -2, audio = -3, networkUngrouped = -4, localUngrouped = -5, video = -6, error = -11
}

public enum BookGroupMembership {
    public static func contains(_ book: BookRow, groupID: Int64, customMask: Int64,
                                networkUngroupedVisible: Bool = false) -> Bool {
        guard book.type & 1024 == 0 else { return false }
        let ungrouped = book.group & customMask == 0
        switch groupID {
        case -1: return true
        case -2: return book.type & 256 != 0
        case -3: return book.type & 32 != 0
        case -6: return book.type & 4 != 0
        case -11: return book.type & 16 != 0
        case -4: return book.type & 292 == 0 && ungrouped
        case -5: return book.type & 256 != 0 && ungrouped
        case -100: return book.type & 8 != 0 && book.type & 256 == 0 && ungrouped && !networkUngroupedVisible
        default: return groupID > 0 && book.group & groupID != 0
        }
    }
}

public enum BookshelfEditError: Error { case invalidGroup, groupLimit, emptyName, missingBook }

extension Repository where Record == BookGroupRow {
    public func ensureBuiltinGroups() async throws {
        try await database.writer.write { db in
            let defaults: [(BuiltinBookGroup, String)] = [(.all, "全部"), (.local, "本地"), (.audio, "音频"),
                (.networkUngrouped, "网络未分组"), (.localUngrouped, "本地未分组"), (.video, "视频"), (.error, "更新失败")]
            for (index, item) in defaults.enumerated() {
                guard try BookGroupRow.fetchOne(db, key: item.0.rawValue) == nil else { continue }
                var group = BookGroupRow(); group.groupId = item.0.rawValue; group.groupName = item.1; group.order = index - defaults.count
                try group.insert(db)
            }
        }
    }

    public func createGroup(name: String) async throws -> BookGroupRow {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BookshelfEditError.emptyName }
        return try await database.writer.write { db in
            let groups = try BookGroupRow.fetchAll(db)
            let used = groups.filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
            guard let bit = (0..<63).map({ Int64(1) << $0 }).first(where: { used & $0 == 0 }) else { throw BookshelfEditError.groupLimit }
            var group = BookGroupRow(); group.groupId = bit; group.groupName = name
            group.order = (groups.map(\.order).max() ?? -1) + 1
            try db.execute(sql: "UPDATE books SET \"group\" = \"group\" & ?", arguments: [~bit])
            try group.insert(db)
            return group
        }
    }

    public func removeCustomGroup(_ id: Int64) async throws {
        guard id > 0, id & (id - 1) == 0 else { throw BookshelfEditError.invalidGroup }
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE books SET \"group\" = \"group\" & ?", arguments: [~id])
            try BookGroupRow.deleteOne(db, key: id)
        }
    }

    public func reorder(_ ids: [Int64]) async throws {
        try await database.writer.write { db in
            for (order, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE book_groups SET \"order\" = ? WHERE groupId = ?", arguments: [order, id])
            }
        }
    }
}

extension Repository where Record == BookRow {
    public func move(bookURLs: [String], from: Int64 = 0, to: Int64) async throws {
        guard from >= 0, to >= 0 else { throw BookshelfEditError.invalidGroup }
        try await database.writer.write { db in
            let mask = try BookGroupRow.fetchAll(db).filter { $0.groupId > 0 }.reduce(Int64(0)) { $0 | $1.groupId }
            guard to & ~mask == 0 else { throw BookshelfEditError.invalidGroup }
            for url in Set(bookURLs) {
                try db.execute(sql: "UPDATE books SET \"group\" = (\"group\" & ?) | ? WHERE bookUrl = ?",
                               arguments: [~from, to, url])
            }
        }
    }

    public func deleteBooks(_ urls: [String]) async throws {
        try await database.writer.write { db in
            for url in Set(urls) { try BookRow.deleteOne(db, key: url) }
        }
    }

    public func saveMetadata(bookURL: String, name: String, author: String, cover: String?, intro: String?,
                             tag: String?, variable: String?) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BookshelfEditError.emptyName }
        try await database.writer.write { db in
            try db.execute(sql: """
                UPDATE books SET name = ?, author = ?, customCoverUrl = ?, customIntro = ?, customTag = ?, variable = ?
                WHERE bookUrl = ?
                """, arguments: [name, author, cover, intro, tag, variable, bookURL])
            guard db.changesCount == 1 else { throw BookshelfEditError.missingBook }
        }
    }

    public func saveChapterUpdate(bookURL: String, chapters: [BookChapterRow], checkedAt: Int64) async throws {
        guard chapters.allSatisfy({ $0.bookUrl == bookURL }) else { throw StorageError.chapterBookMismatch }
        guard !chapters.isEmpty else { throw WebBookError.emptyToc }
        try await database.writer.write { db in
            guard let current = try BookRow.fetchOne(db, key: bookURL) else { throw BookshelfEditError.missingBook }
            let oldChapter = try BookChapterRow.fetchOne(db, sql: "SELECT * FROM chapters WHERE bookUrl = ? AND \"index\" = ?",
                                                        arguments: [bookURL, current.durChapterIndex])
            let ordered = chapters.sorted { $0.index < $1.index }
            let title = current.durChapterTitle.flatMap { $0.isEmpty ? nil : $0 } ?? oldChapter?.title
            let position = BookChapterLocator.locate(oldIndex: current.durChapterIndex, oldTitle: title,
                oldCount: current.totalChapterNum, titles: ordered.map(\.title), oldURL: oldChapter?.url, urls: ordered.map(\.url))
            try db.execute(sql: "DELETE FROM chapters WHERE bookUrl = ?", arguments: [bookURL])
            for var chapter in chapters { try chapter.insert(db) }
            let added = max(0, chapters.count - current.totalChapterNum)
            try db.execute(sql: """
                UPDATE books SET totalChapterNum = ?, latestChapterTitle = ?, lastCheckTime = ?, lastCheckCount = ?,
                latestChapterTime = ?, durChapterIndex = ?, durChapterTitle = ?, type = type & ~16 WHERE bookUrl = ?
                """, arguments: [chapters.count, ordered.last?.title, checkedAt, added > 0 ? added : current.lastCheckCount,
                                  added > 0 ? checkedAt : current.latestChapterTime, position, ordered[position].title, bookURL])
        }
    }

    public func markUpdateFailed(bookURL: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE books SET type = type | 16 WHERE bookUrl = ?", arguments: [bookURL])
        }
    }
}
