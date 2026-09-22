import XCTest
import GRDB
@testable import BookshelfAdvancedCheck

final class ErrorPresentationTests: XCTestCase {
    func testPresentationIncludesOperationObjectAndFile() {
        let value = URLError(.timedOut).presentation(operation: "导入书源", subject: "测试书源",
            sourceFile: "sources.json", actions: [.retry, .manageSources])
        XCTAssertEqual(value?.title, "导入书源失败")
        XCTAssertTrue(value?.message.contains("测试书源") == true)
        XCTAssertTrue(value?.message.contains("sources.json") == true)
        XCTAssertEqual(value?.actions, [.retry, .manageSources])
        XCTAssertNil(URLError(.cancelled).presentation(operation: "加载"))
        let database = DatabaseError(resultCode: .SQLITE_CORRUPT).presentation(operation: "保存进度", subject: "Book")
        XCTAssertEqual(database?.title, "保存进度失败")
    }

    func testRawErrorMessagesStayWithinMigrationAllowlist() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("App/Sources").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { XCTFail("Repository root not found"); return }
            root = parent
        }
        let sources = root.appendingPathComponent("App/Sources")
        let allowlist = root.appendingPathComponent("tools/appcore-check/error-presentation-allowlist.json")
        let allowed = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: allowlist))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var actual: [String: [String]] = [:]
        for case let file as URL in files where file.pathExtension == "swift" {
            let path = String(file.path.dropFirst(root.path.count + 1))
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    guard line.contains("localizedDescription") else { return false }
                    if line.contains("NSLog(") { return false }
                    if line.hasPrefix("AppLogStore.shared.append(") || line.hasPrefix("catch { AppLogStore.shared.append(") { return false }
                    if path == "App/Sources/Shared/ErrorPresentation.swift", line == "return \"操作失败：\" + localizedDescription" { return false }
                    return true
                }.sorted()
            if !lines.isEmpty { actual[path] = lines }
        }
        XCTAssertEqual(actual, allowed, "Migrate new user-facing errors through ErrorPresentation; remove migrated lines from the allowlist.")
    }

    func testNetworkFallbacksAndCancellation() {
        for (code, text): (URLError.Code, String) in [(.notConnectedToInternet, "网络"), (.timedOut, "超时"),
            (.cannotFindHost, "服务器"), (.secureConnectionFailed, "安全连接"), (.serverCertificateUntrusted, "证书")] {
            XCTAssertTrue(URLError(code).presentableMessage?.contains(text) == true)
        }
        XCTAssertNil(URLError(.cancelled).presentableMessage)
        XCTAssertNil(CancellationError().presentableMessage)
    }

    func testDecodingPathAndDatabaseFallback() {
        struct Fixture: Decodable { let entries: [Entry]; struct Entry: Decodable { let count: Int } }
        do {
            _ = try JSONDecoder().decode(Fixture.self, from: Data(#"{"entries":[{"count":"bad"}]}"#.utf8))
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertTrue(error.presentableMessage?.contains("数据格式不正确") == true)
            XCTAssertTrue(error.presentableMessage?.contains("entries[0].count") == true)
        }
        XCTAssertTrue(DatabaseError(resultCode: .SQLITE_CORRUPT).presentableMessage?.contains("本地数据库") == true)
        XCTAssertTrue(NSError(domain: "Fixture", code: 1).presentableMessage?.hasPrefix("操作失败") == true)
    }
}
