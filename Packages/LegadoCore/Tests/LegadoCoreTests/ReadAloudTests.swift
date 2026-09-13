import XCTest
@testable import LegadoCore

@MainActor
final class ReadAloudTests: XCTestCase {
    final class FakeSpeaker: Speaker {
        var completion: ((Result<Void, Error>) -> Void)?
        var spoken: [String] = []
        var paused = false
        func speak(_ text: String, rate: Double, volume: Double, completion: @escaping (Result<Void, Error>) -> Void) {
            spoken.append(text); self.completion = completion
        }
        func pause() { paused = true }
        func resume() { paused = false }
        func stop() { completion = nil }
    }
    func testParagraphOffsetsAndPlayback() {
        let speaker = FakeSpeaker(), engine = ReadAloudEngine(speaker: FakeSpeaker())
        engine.replaceSpeaker(speaker)
        engine.load(text: "甲\n\n乙😀\n丙", chapter: 2)
        XCTAssertEqual(engine.paragraphs.map(\.range.location), [0, 3, 7])
        engine.play(); XCTAssertEqual(engine.state, .playing)
        speaker.completion?(.success(()))
        XCTAssertEqual(engine.paragraphIndex, 1)
        engine.pause(); XCTAssertEqual(engine.state, .paused)
        engine.play(); XCTAssertFalse(speaker.paused)
        engine.previous(); XCTAssertEqual(engine.paragraphIndex, 0)
        engine.stop(); XCTAssertEqual(engine.state, .stopped)
    }
    func testStaleCompletionAndChapterEnd() async {
        let speaker = FakeSpeaker(), engine = ReadAloudEngine(speaker: FakeSpeaker())
        engine.replaceSpeaker(speaker)
        engine.load(text: "甲", chapter: 0)
        var requested = 0
        engine.nextChapter = { requested += 1; return .init(index: 1, text: "乙") }
        engine.play()
        let stale = speaker.completion
        engine.stop(); stale?(.success(()))
        XCTAssertEqual(engine.state, .stopped)
        engine.play(); speaker.completion?(.success(()))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(requested, 1); XCTAssertEqual(engine.chapterIndex, 1)
        XCTAssertEqual(speaker.spoken.last, "乙")
    }
    func testTimerUsesInjectedClockAndFreezesPausedPlayback() {
        var time = Date(timeIntervalSince1970: 100)
        let engine = ReadAloudEngine(speaker: FakeSpeaker(), now: { time })
        engine.load(text: "甲", chapter: 0); engine.play(); engine.setTimer(seconds: 10)
        engine.pause(); time = time.addingTimeInterval(9); engine.checkTimer()
        XCTAssertEqual(engine.state, .paused)
        time = time.addingTimeInterval(1); engine.checkTimer()
        XCTAssertEqual(engine.state, .paused); XCTAssertNil(engine.stopAt)
        engine.play(); time = time.addingTimeInterval(10); engine.checkTimer()
        XCTAssertEqual(engine.state, .stopped)
    }
    func testEmptyAndFailure() {
        let speaker = FakeSpeaker(), engine = ReadAloudEngine(speaker: FakeSpeaker())
        engine.replaceSpeaker(speaker); engine.load(text: " \n", chapter: 0); engine.play()
        XCTAssertEqual(engine.state, .stopped)
        engine.load(text: "甲", chapter: 0); engine.play()
        speaker.completion?(.failure(URLError(.cannotDecodeContentData)))
        XCTAssertEqual(engine.state, .stopped); XCTAssertNotNil(engine.errorMessage)
    }
    func testTimerSurvivesLoadAndPause() {
        var time = Date(timeIntervalSince1970: 100)
        let speaker = FakeSpeaker(), engine = ReadAloudEngine(speaker: FakeSpeaker(), now: { time })
        engine.replaceSpeaker(speaker); engine.setTimer(seconds: 10)
        engine.load(text: "甲", chapter: 0)
        XCTAssertEqual(engine.remainingSeconds, 10)
        engine.play(); engine.pause(); time = time.addingTimeInterval(10)
        engine.play()
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(speaker.spoken.count, 1)
    }
    func testHTTPRetriesAndRejectsTextResponse() async throws {
        let client = ReplayHttpClient(), url = URL(string: "https://tts.test/retry")!
        await client.enqueue(url: url, error: URLError(.timedOut))
        await client.enqueue(url: url, response: .init(status: 200, body: Data([7]), finalURL: url))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-retry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HttpTTSSource(source: .init(id: 2, name: "重试", url: url.absoluteString), client: client, directory: directory)
        _ = try await service.audio(text: "甲", speed: 10)
        let count = await client.requests.count; XCTAssertEqual(count, 2)
        for _ in 0..<3 { await client.enqueue(url: url, response: .init(status: 200, body: Data("错误".utf8), finalURL: url, headers: ["Content-Type": "text/plain"])) }
        do { _ = try await service.audio(text: "乙", speed: 10); XCTFail("文字响应不能缓存为音频") }
        catch HttpTTSSource.SynthesisError.invalidContentType { }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
    }
    func testHttpRuleAndCache() async throws {
        let client = ReplayHttpClient(), url = URL(string: "https://tts.test/hello/5")!
        await client.enqueue(url: url, response: .init(status: 200, body: Data([1, 2, 3]), finalURL: url, headers: ["Content-Type": "audio/mpeg"]))
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = HttpTTSSource(source: .init(id: 1, name: "测试", url: "https://tts.test/{{speakText}}/{{speakSpeed}}"), client: client, directory: directory)
        let first = try await service.audio(text: "hello", speed: 5)
        let second = try await service.audio(text: "hello", speed: 5)
        XCTAssertEqual(first, second); XCTAssertEqual(try Data(contentsOf: first), Data([1, 2, 3]))
        let requests = await client.requests; XCTAssertEqual(requests.count, 1)
    }
    func testEntityDefaultsAndBackup() async throws {
        let entity = try GsonJSONDecoder(now: { 123 }).decode(HttpTTS.self, from: Data(#"{"name":"源","url":"https://tts.test"}"#.utf8))
        XCTAssertEqual(entity.id, 123); XCTAssertEqual(entity.concurrentRate, "0")
        let database = try AppDatabase.inMemory()
        let archive = BackupReviewTests.archive(["httpTTS.json": #"[{"id":1,"name":"源","url":"https://tts.test"}]"#])
        let report = try await BackupImporter(database: database, localDeviceID: "test").importArchive(archive)
        XCTAssertEqual(report.importedCounts["httpTTS.json"], 1)
        let sources = try await HttpTTSRepository(database: database).list()
        XCTAssertEqual(sources.first?.name, "源")
    }
}
