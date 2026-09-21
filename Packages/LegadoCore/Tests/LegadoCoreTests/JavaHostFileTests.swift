import XCTest
@testable import LegadoCore

final class JavaHostFileTests: XCTestCase {
    func testFileBytesTextMetadataAndDelete() async throws {
        let store = MemoryHostDownloadStore()
        _ = try await store.save(Data([65, 195, 169]), path: "/sample.txt")
        let engine = JsEngine(downloadStore: store)
        XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(java.readFile('/sample.txt'))") as? String, "A\u{00e9}")
        XCTAssertEqual(try engine.evaluateScript("java.readTxtFile('/sample.txt','UTF-8')") as? String, "A\u{00e9}")
        XCTAssertEqual(try engine.evaluateScript("java.readTxtFile('/sample.txt')") as? String, "A\u{00e9}")
        XCTAssertEqual(try engine.evaluateScript("var f=java.getFile('/sample.txt');[f.exists(),f.isFile(),f.getName(),f.length()].join('|')") as? String, "true|true|sample.txt|3")
        XCTAssertEqual(try engine.evaluateScript("java.deleteFile('/sample.txt')") as? Bool, true)
        XCTAssertNil(try engine.evaluateScript("java.readFile('/sample.txt')"))
        XCTAssertEqual(try engine.evaluateScript("java.readTxtFile('/sample.txt')") as? String, "")
        XCTAssertThrowsError(try engine.evaluateScript("java.readFile('../../outside')"))
    }

    func testImportScriptReadsLocalAndCachedNetworkText() async throws {
        let store = MemoryHostDownloadStore(), client = ReplayHttpClient()
        _ = try await store.save(Data("21 + 21".utf8), path: "/script.js")
        let url = URL(string: "https://fixture.test/script.js")!
        await client.enqueue(url: url, response: HttpResponse(status: 200, body: Data("6 * 7".utf8), finalURL: url))
        let engine = JsEngine(httpClient: client, cacheManager: CacheManager(directory: nil), downloadStore: store)
        XCTAssertEqual(try engine.evaluateScript("eval(java.importScript('/script.js'))") as? Double, 42)
        for _ in 0..<2 {
            XCTAssertEqual(try engine.evaluateScript("eval(java.importScript('https://fixture.test/script.js'))") as? Double, 42)
        }
        XCTAssertThrowsError(try engine.evaluateScript("java.importScript('/missing.js')"))
    }
    func testAllArchiveEntryAndExtractionMethods() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = [
            ("Zip", "Tests/Fixtures/localbook/two-books.zip", "First.txt", "unzipFile"),
            ("Rar", "tools/archive-probe/Tests/ArchiveProbeTests/Fixtures/rar5.rar", "chapter.txt", "unrarFile"),
            ("7z", "tools/archive-probe/Tests/ArchiveProbeTests/Fixtures/lzma2-solid.7z", "chapter.txt", "un7zFile")
        ]
        for (kind, file, entry, method) in fixtures {
            let url = root.appendingPathComponent(file), bytes = try Data(contentsOf: url)
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            let expected = try BookArchive(url: url).read(entry)
            let expectedText = String(decoding: expected, as: UTF8.self)
            let store = MemoryHostDownloadStore()
            let path = try await store.save(bytes, path: "/" + url.lastPathComponent)
            let engine = JsEngine(downloadStore: store)
            XCTAssertEqual(try engine.evaluateScript("java.get\(kind)StringContent('\(hex)','\(entry)')") as? String, expectedText)
            XCTAssertEqual(try engine.evaluateScript("java.get\(kind)StringContent('\(hex)','\(entry)','UTF-8')") as? String, expectedText)
            XCTAssertEqual(try engine.evaluateScript("java.bytesToStr(java.get\(kind)ByteArrayContent('\(hex)','\(entry)'))") as? String, expectedText)
            XCTAssertNil(try engine.evaluateScript("java.get\(kind)ByteArrayContent('\(hex)','missing')"))
            XCTAssertEqual(try engine.evaluateScript("java.get\(kind)StringContent('\(hex)','missing')") as? String, "")
            for unpack in [method, "unArchiveFile"] {
                let folder = try XCTUnwrap(engine.evaluateScript("java.\(unpack)('\(path)')") as? String)
                XCTAssertTrue(folder.hasPrefix("ArchiveTemp/"))
                XCTAssertEqual(try engine.evaluateScript("java.readTxtFile('\(folder)/\(entry)')") as? String, expectedText)
                XCTAssertEqual(try engine.evaluateScript("java.deleteFile('\(folder)')") as? Bool, true)
            }
        }
    }

    func testFolderTextIsJoinedAndRemoved() async throws {
        let store = MemoryHostDownloadStore()
        _ = try await store.save(Data("One".utf8), path: "folder/1.txt")
        _ = try await store.save(Data("Two".utf8), path: "folder/2.txt")
        let engine = JsEngine(downloadStore: store)
        XCTAssertEqual(try engine.evaluateScript("java.getTxtInFolder('folder')") as? String, "One\nTwo")
        XCTAssertEqual(try engine.evaluateScript("java.getFile('folder').exists()") as? Bool, false)
        XCTAssertEqual(try engine.evaluateScript("java.getTxtInFolder('absent')") as? String, "")
    }

    func testDiskStorePersistsAndRejectsEscapingLinksAndOversizedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("files"), outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let store = DiskHostDownloadStore(directory: directory, maximumSize: 4)
        _ = try await store.save(Data("Body".utf8), path: "nested/body")
        let reopened = DiskHostDownloadStore(directory: directory)
        let data = try await reopened.read("/nested/body")
        XCTAssertEqual(data, Data("Body".utf8))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: outside)
        for path in ["../outside/file", "link/file", ".", "/", "file://outside"] {
            do { _ = try await store.save(Data(), path: path); XCTFail("Accepted unsafe path: " + path) }
            catch { XCTAssertFalse(error is CancellationError) }
        }
        do { _ = try await store.save(Data("Large".utf8), path: "large"); XCTFail("Accepted oversized content") }
        catch BookArchiveError.sizeLimit { }
    }

}
