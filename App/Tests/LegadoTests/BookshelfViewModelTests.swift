import XCTest
import LegadoCore
@testable import Legado

@MainActor
final class BookshelfViewModelTests: XCTestCase {
    func testLastReadSortingAndGroupFiltering() async throws {
        let container = try AppContainer.inMemory()
        var older = BookRow()
        older.bookUrl = "book:older"
        older.name = "较早阅读"
        older.group = 1
        older.durChapterTime = 100
        var newer = BookRow()
        newer.bookUrl = "book:newer"
        newer.name = "最近阅读"
        newer.group = 2
        newer.durChapterTime = 200
        try await container.bookshelf.upsert([older, newer])
        let model = BookshelfViewModel(bookshelf: container.bookshelf, groups: container.bookGroups)

        await model.load()
        XCTAssertEqual(model.books.map(\.bookUrl), [newer.bookUrl, older.bookUrl])
        XCTAssertFalse(model.isEmpty)
        model.selectedGroupID = 1
        await model.load()
        XCTAssertEqual(model.books.map(\.bookUrl), [older.bookUrl])
        model.selectedGroupID = 4
        await model.load()
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.errorMessage)
    }
}
