import XCTest
import GRDB
import LegadoCore

final class AppDatabaseTransactionTests: XCTestCase {
    private enum Failure: Error { case secondWrite }

    func testWriteCommitsBothStepsAndReturnsValue() async throws {
        let database = try AppDatabase.inMemory()
        let count = try await database.write { db in
            var first = BookRow(); first.bookUrl = "first"; first.name = "甲"
            var second = BookRow(); second.bookUrl = "second"; second.name = "乙"
            try first.insert(db)
            try second.insert(db)
            return try BookRow.fetchCount(db)
        }
        XCTAssertEqual(count, 2)
        let stored = try await BookshelfRepository(database: database).all()
        XCTAssertEqual(stored.count, 2)
    }

    func testSecondStepFailureRollsBackFirstWrite() async throws {
        let database = try AppDatabase.inMemory()
        do {
            try await database.write { db in
                var first = BookRow(); first.bookUrl = "first"; first.name = "甲"
                try first.insert(db)
                throw Failure.secondWrite
            }
            XCTFail("事务必须抛出第二步错误")
        } catch Failure.secondWrite {}
        let stored = try await BookshelfRepository(database: database).all()
        XCTAssertTrue(stored.isEmpty)
    }
}
