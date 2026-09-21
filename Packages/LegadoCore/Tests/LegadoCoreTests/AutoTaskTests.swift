import XCTest
@testable import LegadoCore

final class AutoTaskTests: XCTestCase {
    func testCronStepsAndDayUnion() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 10, minute: 12))!
        let schedule = try CronSchedule("*/30 * * * *")
        XCTAssertEqual(schedule.next(after: start, calendar: calendar), start.addingTimeInterval(18*60))
        XCTAssertThrowsError(try CronSchedule("*/0 * * * *"))
        XCTAssertThrowsError(try CronSchedule("0 25 * * *"))
        XCTAssertThrowsError(try CronSchedule("0 0 ? * *"))
        XCTAssertEqual(try CronSchedule("0 0 22 * 1").next(after: start, calendar: calendar), calendar.date(from: DateComponents(year: 2026,month: 9,day: 22)))
    }

    func testTaskEvaluationPersistsResultAndFailure() async throws {
        let db = try AppDatabase.inMemory(), client = ReplayHttpClient()
        var rule = AutoTaskRule(); rule.id = "fixture"; rule.name = "Fixture"; rule.script = "@js: 6*7"
        var result = try await AutoTaskRunner.run(rule, database: db, client: client) { _ in "action" }
        XCTAssertEqual(result.lastResult, "42.0"); XCTAssertNil(result.lastError)
        rule.script = "throw Error('fixture failure')"
        result = try await AutoTaskRunner.run(rule, database: db, client: client) { _ in "action" }
        XCTAssertTrue(result.lastError?.contains("fixture failure") == true)
        let stored = try await AutoTaskRuleRepository(database: db).all()
        XCTAssertEqual(stored.count, 1); XCTAssertEqual(stored.first?.lastError, result.lastError)
        rule.script = "({actions:[{type:'notify',content:'hello'}]})"
        result = try await AutoTaskRunner.run(rule, database: db, client: client) { action in
            XCTAssertEqual(action["content"] as? String, "hello"); return "notified"
        }
        XCTAssertTrue(result.lastLog?.contains("notified") == true)
    }
}
