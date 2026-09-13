import XCTest
import CryptoKit
@testable import LegadoCore

final class HttpTTSCacheIdentityTests: XCTestCase {
    func testCanonicalIdentitySurvivesRepeatedCallsAndServiceRecreation() async throws {
        let source = HttpTTS(id: 71, name: "缓存身份", url: "https://tts.test/identity")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-identity-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: source.url)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data([1, 2, 3]), finalURL: url))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let canonical = try encoder.encode(source)
        let expected = SHA256.hash(data: canonical + Data("\u{0}10\u{0}正文".utf8)).map { String(format: "%02x", $0) }.joined() + ".audio"
        let service = HttpTTSSource(source: source, client: client, directory: directory, now: { Date(timeIntervalSince1970: 100) })
        let first = try await service.audio(text: "正文", speed: 10)
        XCTAssertEqual(try Data(contentsOf: first), Data([1, 2, 3]))
        XCTAssertEqual(first.lastPathComponent, expected)
        for _ in 0..<32 { let next = try await service.audio(text: "正文", speed: 10); XCTAssertEqual(first, next) }
        let reopened = HttpTTSSource(source: source, client: client, directory: directory, now: { Date(timeIntervalSince1970: 100) })
        let restored = try await reopened.audio(text: "正文", speed: 10)
        XCTAssertEqual(first, restored)
        let requests = await client.requests; XCTAssertEqual(requests.count, 1)
    }
    func testPlaybackProtectionAndPrefetchUseTheSameIdentity() async throws {
        let source = HttpTTS(id: 72, name: "文件保护", url: "https://tts.test/protection")
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-protection-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: source.url)!
        await client.enqueue(url: url, response: .init(status: 200, body: Data([1]), finalURL: url))
        let service = HttpTTSSource(source: source, client: client, directory: directory, maximumCacheBytes: 0, now: { Date(timeIntervalSince1970: 100) })
        try await service.withAudio(text: "正文", speed: 10) { file in
            await service.prefetch(texts: ["正文"], speed: 10)
            try await service.trimCache()
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
        let requests = await client.requests; XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
