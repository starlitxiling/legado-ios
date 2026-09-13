import XCTest
@testable import LegadoCore

final class BackupReviewTests: XCTestCase {
    func testZeroIDsGenerateAndDuplicateExplicitIDsReplace() async throws {
        let db = try AppDatabase.inMemory()
        var prior = ReplaceRuleRow(); prior.id = 7; prior.name = "prior"
        try await ReplaceRuleRepository(database: db).upsert(prior)
        let json = #"[{"id":0,"name":"first"},{"id":0,"name":"second"},{"id":7,"name":"old"},{"id":7,"name":"last"}]"#
        let report = try await BackupImporter(database: db, localDeviceID: "local").importArchive(Self.archive(["replaceRule.json": json]))
        let rows = try await ReplaceRuleRepository(database: db).all()
        XCTAssertEqual(Set(rows.map(\.name)), Set(["first", "second", "last"]))
        XCTAssertFalse(rows.contains { $0.id == 0 })
        XCTAssertEqual(report.importedCounts["replaceRule.json"], 3)
    }

    func testPreviewLossIsReportedAndPersistentFieldsSurvive() async throws {
        let db = try AppDatabase.inMemory()
        let json = #"[{"id":7,"previewText":"sample","group":"group","pattern":"pattern","replacement":"replacement","scope":"scope","scopeTitle":true,"scopeSource":true,"scopeContent":false,"excludeScope":"excluded","isEnabled":false,"isRegex":false,"timeoutMillisecond":17,"order":19}]"#
        let report = try await BackupImporter(database: db, localDeviceID: "local").importArchive(Self.archive(["replaceRule.json": json]))
        XCTAssertEqual(report.discardedFields["replaceRule.json"], ["previewText"])
        let row = try await ReplaceRuleRepository(database: db).get(id: 7)
        XCTAssertEqual(row?.group, "group"); XCTAssertEqual(row?.pattern, "pattern")
        XCTAssertEqual(row?.replacement, "replacement"); XCTAssertEqual(row?.scope, "scope")
        XCTAssertEqual(row?.scopeTitle, true); XCTAssertEqual(row?.scopeSource, true)
        XCTAssertEqual(row?.scopeContent, false); XCTAssertEqual(row?.excludeScope, "excluded")
        XCTAssertEqual(row?.isEnabled, false); XCTAssertEqual(row?.isRegex, false)
        XCTAssertEqual(row?.timeoutMillisecond, 17); XCTAssertEqual(row?.order, 19)
    }

    func testOneInvalidArrayEntryRejectsEntireFile() async throws {
        let db = try AppDatabase.inMemory()
        let report = try await BackupImporter(database: db, localDeviceID: "local").importArchive(Self.archive([
            "replaceRule.json": #"[{"id":1,"name":"valid"},{"id":{}}]"#,
            "bookmark.json": #"[{"time":1}]"#]))
        let rows = try await ReplaceRuleRepository(database: db).all()
        XCTAssertTrue(rows.isEmpty)
        XCTAssertNotNil(report.failures["replaceRule.json"])
        XCTAssertEqual(report.importedCounts["bookmark.json"], 1)
    }

    static func archive(_ files: [String: String]) -> Data {
        var data = Data(), central = Data()
        func number(_ value: Int, _ width: Int) -> Data {
            Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        for name in files.keys.sorted() {
            let body = Data(files[name]!.utf8), filename = Data(name.utf8), offset = data.count
            var crc: UInt32 = .max
            for byte in body {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
            }
            crc ^= .max
            data += number(0x04034b50, 4) + number(20, 2) + Data(repeating: 0, count: 8)
            data += number(Int(crc), 4) + number(body.count, 4) + number(body.count, 4)
            data += number(filename.count, 2) + number(0, 2) + filename + body
            central += number(0x02014b50, 4) + number(20, 2) + number(20, 2) + Data(repeating: 0, count: 8)
            central += number(Int(crc), 4) + number(body.count, 4) + number(body.count, 4)
            central += number(filename.count, 2) + Data(repeating: 0, count: 12) + number(offset, 4) + filename
        }
        let offset = data.count
        data += central
        data += number(0x06054b50, 4) + Data(repeating: 0, count: 4)
        data += number(files.count, 2) + number(files.count, 2) + number(central.count, 4) + number(offset, 4) + number(0, 2)
        return data
    }
}
