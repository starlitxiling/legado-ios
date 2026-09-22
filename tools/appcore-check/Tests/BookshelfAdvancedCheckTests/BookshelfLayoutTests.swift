import XCTest
import LegadoCore
import GRDB
@testable import BookshelfAdvancedCheck

final class BookshelfLayoutTests: XCTestCase {
    func testCancellationPresentationRecognizesBridgedAndWrappedErrors() {
        let cancelled = CancellationError() as NSError
        let errors: [Error] = [CancellationError(), cancelled,
            NSError(domain: cancelled.domain, code: cancelled.code), URLError(.cancelled),
            NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue),
            DatabaseError(resultCode: .SQLITE_INTERRUPT),
            NSError(domain: "Storage", code: 1, userInfo: [NSUnderlyingErrorKey: cancelled])]
        for error in errors {
            XCTAssertTrue(error.isCancellation, String(describing: error))
            XCTAssertNil(error.presentableMessage)
        }
        for error: Error in [URLError(.timedOut), DatabaseError(resultCode: .SQLITE_ABORT),
                            DatabaseError(resultCode: .SQLITE_CORRUPT), CocoaError(.fileReadCorruptFile)] {
            XCTAssertFalse(error.isCancellation)
            XCTAssertNotNil(error.presentableMessage)
        }
    }

    @MainActor
    func testCancelledBookshelfReadDoesNotBecomeUserError() async throws {
        let groups = BookGroupRepository(database: try AppDatabase.inMemory())
        let model = BookshelfViewModel(bookshelf: CancelledBookshelfReading(), groups: groups)
        await model.load()
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testSevenLayoutsAndProgressCompatibility() {
        XCTAssertEqual(BookshelfLayout.allCases.count, 7)
        XCTAssertEqual(BookshelfLayout.allCases.compactMap(\.columns), [2, 3, 4, 5, 6])
        XCTAssertEqual(BookshelfLayout.list.coverWidth, 66)
        XCTAssertEqual(BookshelfLayout.list.coverHeight, 90)
        XCTAssertEqual(BookshelfLayout.compact.coverWidth, 48)
        XCTAssertEqual(BookshelfLayout.compact.coverHeight, 64)
        XCTAssertEqual(BookshelfProgressMode(storedMode: nil, legacyEnabled: nil), .standard)
        XCTAssertEqual(BookshelfProgressMode(storedMode: nil, legacyEnabled: false), .hidden)
        XCTAssertEqual(BookshelfProgressMode(storedMode: 2, legacyEnabled: false), .enhanced)
        XCTAssertEqual(BookshelfProgressMode(storedMode: -3, legacyEnabled: true), .hidden)
        XCTAssertEqual(BookshelfProgressMode(storedMode: 9, legacyEnabled: nil), .enhanced)
    }

    func testProgressMatchesChapterIndexContractAndClampsInvalidBounds() {
        XCTAssertNil(BookshelfBookMetrics(total: 10, chapter: 0, position: 0).progress)
        XCTAssertEqual(BookshelfBookMetrics(total: 10, chapter: 0, position: 2).progress, 0)
        XCTAssertEqual(BookshelfBookMetrics(total: 11, chapter: 5, position: 0).progress, 0.5)
        XCTAssertEqual(BookshelfBookMetrics(total: 11, chapter: 5, position: 0).unread, 5)
        XCTAssertEqual(BookshelfBookMetrics(total: 1, chapter: 0, position: 1).progress, 1)
        XCTAssertEqual(BookshelfBookMetrics(total: 10, chapter: 100, position: 0).unread, 0)
        XCTAssertEqual(BookshelfBookMetrics(total: Int.max, chapter: Int.min, position: 0).unread, Int.max - 1)
        XCTAssertEqual(BookshelfBookMetrics(total: 10, chapter: -1, position: 0).progress, 0)
    }

    @MainActor
    func testFolderRootUsesVisibleGroupsAndOrderedFourBookPreviews() async throws {
        let database = try AppDatabase.inMemory()
        let groups = BookGroupRepository(database: database)
        var all = BookGroupRow(); all.groupId = -1; all.groupName = "All"; all.order = -1
        var custom = BookGroupRow(); custom.groupId = 2; custom.groupName = "Custom"; custom.bookSort = 2
        var hidden = BookGroupRow(); hidden.groupId = 4; hidden.groupName = "Hidden"; hidden.show = false
        try await groups.upsert([all, custom, hidden])
        let shelf = BookshelfRepository(database: database)
        for index in 0..<6 {
            var book = BookRow(); book.bookUrl = "book:" + String(index); book.name = "Book" + String(index)
            book.type = 8; book.group = index < 4 ? 2 : 0; book.durChapterTime = Int64(100 - index)
            if index == 5 { book.durChapterPos = 1 }
            try await shelf.insert(book)
        }
        let model = BookshelfViewModel(bookshelf: shelf, groups: groups)
        model.folderMode = true; model.selectedGroupID = -100
        await model.load()
        XCTAssertEqual(model.books.count, 2)
        XCTAssertEqual(model.groups.map(\.groupId), [-1, 2])
        XCTAssertEqual(model.groupCounts[-1], 6)
        XCTAssertEqual(model.groupPreviews[-1]?.count, 4)
        XCTAssertEqual(model.groupPreviews[2]?.map(\.name), ["Book0", "Book1", "Book2", "Book3"])
        model.selectedGroupID = 2
        await model.load()
        XCTAssertEqual(model.books.count, 4)
        XCTAssertTrue(model.groupPreviews.isEmpty)
        XCTAssertEqual(model.shelfBookCount, 6)
        XCTAssertEqual(model.readingCount, 1)
        XCTAssertEqual(model.recentBook?.bookUrl, "book:5")
    }
}

private struct CancelledBookshelfReading: BookshelfReading {
    func list(groupID: Int64, sort: BookshelfSort) async throws -> [BookRow] {
        throw CancellationError()
    }
}
