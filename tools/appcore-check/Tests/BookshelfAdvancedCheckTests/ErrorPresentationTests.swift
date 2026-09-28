import XCTest
import GRDB
@testable import BookshelfAdvancedCheck

final class ErrorPresentationTests: XCTestCase {
    func testFilePermissionsAndBrokenJSONKeepFileContext() {
        let permission = CocoaError(.fileReadNoPermission).presentation(operation: "导入书籍", sourceFile: "Book.epub")
        XCTAssertTrue(permission?.message.contains("权限") == true)
        XCTAssertTrue(permission?.message.contains("Book.epub") == true)
        do {
            _ = try JSONSerialization.jsonObject(with: Data("{invalid".utf8))
            XCTFail("Expected invalid JSON")
        } catch {
            let message = error.presentation(operation: "恢复备份", sourceFile: "bookshelf.json")
            XCTAssertTrue(message?.message.contains("数据格式不正确") == true)
            XCTAssertTrue(message?.message.contains("bookshelf.json") == true)
        }
    }

    func testPresentationIncludesOperationObjectAndFile() {
        let value = URLError(.timedOut).presentation(operation: "导入书源", subject: "测试书源",
            sourceFile: "sources.json", actions: [.retry, .manageSources])
        XCTAssertEqual(value?.title, "导入书源失败")
        XCTAssertTrue(value?.message.contains("测试书源") == true)
        XCTAssertTrue(value?.message.contains("sources.json") == true)
        XCTAssertEqual(value?.actions, [.retry, .manageSources])
        XCTAssertNotNil(URLError(.cancelled).presentation(operation: "加载"))
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
            let lines = Self.rawErrorStatements(try String(contentsOf: file, encoding: .utf8), path: path).sorted()
            if !lines.isEmpty { actual[path] = lines }
        }
        XCTAssertEqual(actual, allowed, "Migrate new user-facing errors through ErrorPresentation; remove migrated lines from the allowlist.")
    }

    func testRawErrorScannerOnlyExemptsWholeLoggingStatements() {
        XCTAssertEqual(Self.rawErrorStatements(#"NSLog("%@", error.localizedDescription); state = String(describing: error)"#).count, 1)
        XCTAssertEqual(Self.rawErrorStatements(#"catch { AppLogStore.shared.append("\(error)"); state = "\(failure)" }"#).count, 1)
        XCTAssertTrue(Self.rawErrorStatements(#"catch { NSLog("%@", error.localizedDescription) }"#).isEmpty)
        XCTAssertEqual(Self.rawErrorStatements(#"state = String(describing: failure)"#).count, 1)
        XCTAssertTrue(Self.rawErrorStatements(#"load(callback: { catch { NSLog("%@", error.localizedDescription) } })"#).isEmpty)
    }

    private static func rawErrorStatements(_ source: String, path: String = "") -> [String] {
        var statements: [String] = [], current = ""
        var quoted = false, escaped = false, depth = 0
        var blocks = [0]
        for character in source {
            if quoted {
                current.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
                continue
            }
            if character == "\"" { quoted = true }
            if character == "(" || character == "[" { depth += 1 }
            if character == ")" || character == "]" { depth -= 1 }
            if character == "{" || character == "}" || (depth == blocks.last && [";", "\n"].contains(character)) {
                if character == "{" { blocks.append(depth) }
                if character == "}", blocks.count > 1 { blocks.removeLast() }
                statements.append(current.trimmingCharacters(in: .whitespacesAndNewlines)); current = ""
            } else { current.append(character) }
        }
        statements.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return statements.filter { statement in
            guard !statement.hasPrefix("//"), statement.range(of: #"localizedDescription|String\s*\(\s*describing:\s*(error|failure)\s*\)|\\\((error|failure)\)"#, options: .regularExpression) != nil else { return false }
            if statement.range(of: #"^(NSLog|AppLogStore\.shared\.append|(?:self\.)?log\.append)\s*\([\s\S]*\)$"#, options: .regularExpression) != nil { return false }
            if path == "App/Sources/Shared/ErrorPresentation.swift", statement == "return \"操作失败：\" + localizedDescription" { return false }
            return true
        }
    }

    func testNetworkFallbacksAndCancellation() {
        for (code, text): (URLError.Code, String) in [(.notConnectedToInternet, "网络"), (.timedOut, "超时"),
            (.cannotFindHost, "服务器"), (.secureConnectionFailed, "安全连接"), (.serverCertificateUntrusted, "证书")] {
            XCTAssertTrue(URLError(code).presentableMessage?.contains(text) == true)
        }
        XCTAssertNotNil(URLError(.cancelled).presentableMessage)
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
