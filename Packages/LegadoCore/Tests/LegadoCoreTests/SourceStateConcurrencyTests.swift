import XCTest
@testable import LegadoCore

final class SourceStateConcurrencyTests: XCTestCase {
    func testSynchronousStateReadsDoNotDeadlockReaderPoolUnderConcurrency() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try AppDatabase.file(at: directory.appendingPathComponent("db.sqlite").path)
        let repository = SourceStateRepository(database: database)
        try await repository.save(source: "https://s.test", values: ["v_k": "1"])
        let finished = await withTaskGroup(of: Bool.self) { outer -> Bool in
            outer.addTask {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<(ProcessInfo.processInfo.activeProcessorCount * 8) {
                        group.addTask {
                            for _ in 0..<40 {
                                _ = try? await repository.load(source: "https://s.test")
                                _ = try? repository.value(source: "https://s.test", key: "v_k")
                            }
                        }
                    }
                }
                return true
            }
            outer.addTask { try? await Task.sleep(for: .seconds(20)); return false }
            let first = await outer.next() ?? false
            outer.cancelAll()
            return first
        }
        XCTAssertTrue(finished, "source state reads deadlocked")
        XCTAssertEqual(try repository.value(source: "https://s.test", key: "v_k"), "1")
    }
}
