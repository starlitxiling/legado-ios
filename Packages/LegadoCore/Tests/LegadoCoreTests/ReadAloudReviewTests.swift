import XCTest
@testable import LegadoCore

@MainActor
final class ReadAloudReviewTests: XCTestCase {
    func test1FailureWhilePausedIsReportedAndRetryable() {
        let speaker = ReadAloudTests.FakeSpeaker(), engine = ReadAloudEngine(speaker: ReadAloudTests.FakeSpeaker())
        engine.replaceSpeaker(speaker); engine.load(text: "甲乙", chapter: 0); engine.play()
        let callback = speaker.completion
        engine.pause(); callback?(.failure(URLError(.cannotDecodeContentData)))
        XCTAssertEqual(engine.state, .stopped)
        XCTAssertNotNil(engine.errorMessage)
        engine.play(); XCTAssertEqual(speaker.spoken.count, 2)
        engine.stop(); callback?(.failure(URLError(.timedOut)))
        XCTAssertNil(engine.errorMessage)
    }
    func test3StartInsideParagraphPreservesAbsoluteOffset() {
        let speaker = ReadAloudTests.FakeSpeaker(), engine = ReadAloudEngine(speaker: ReadAloudTests.FakeSpeaker())
        engine.replaceSpeaker(speaker)
        var position = -1
        engine.progress = { _, range in position = range.location }
        engine.load(text: "甲😀乙丙\n下一段", chapter: 0, offset: 3); engine.play()
        XCTAssertEqual(speaker.spoken.last, "乙丙")
        XCTAssertEqual(position, 3)
        speaker.completion?(.success(()))
        XCTAssertEqual(speaker.spoken.last, "下一段"); XCTAssertEqual(position, 6)
    }
    func test5PauseDoesNotConsumeTimer() {
        var time = Date(timeIntervalSince1970: 0)
        let engine = ReadAloudEngine(speaker: ReadAloudTests.FakeSpeaker(), now: { time })
        engine.load(text: "测试", chapter: 0); engine.setTimer(seconds: 10); engine.play()
        time = time.addingTimeInterval(3); engine.pause()
        time = time.addingTimeInterval(100); engine.checkTimer()
        XCTAssertEqual(engine.state, .paused)
        engine.play(); time = time.addingTimeInterval(6); engine.checkTimer()
        XCTAssertEqual(engine.state, .playing)
        time = time.addingTimeInterval(1); engine.checkTimer()
        XCTAssertEqual(engine.state, .stopped)
    }
    func test2SourceBridgeAndLoginCheckPersistVariable() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-bridge-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = HttpTTS(id: 2, name: "bridge", url: "https://tts.test/{{source.getVariable() || 'first'}}")
        source.loginCheckJs = "source.setVariable('saved'); result"
        let client = ReplayHttpClient()
        for path in ["first", "saved"] {
            let url = URL(string: "https://tts.test/\(path)")!
            await client.enqueue(url: url, response: .init(status: 200, body: Data([1]), finalURL: url))
        }
        let database = try AppDatabase.inMemory()
        let service = HttpTTSSource(source: source, client: client, directory: directory, database: database)
        _ = try await service.audio(text: "甲", speed: 10)
        let reopened = HttpTTSSource(source: source, client: client, directory: directory, database: database)
        _ = try await reopened.audio(text: "乙", speed: 10)
        let paths = await client.requests.map(\.url.lastPathComponent)
        XCTAssertEqual(paths, ["first", "saved"])
    }
    func test2LoginDefinitionsAndBinaryReplacementResponse() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-login-replace-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = HttpTTS(id: 22, name: "login", url: "https://tts.test/first")
        source.loginUrl = "@js:function login(){source.setVariable('ok')}"
        source.loginCheckJs = "login(); java.get('https://tts.test/audio', {}).raw()"
        let client = ReplayHttpClient()
        let first = URL(string: source.url)!, audio = URL(string: "https://tts.test/audio")!
        await client.enqueue(url: first, response: .init(status: 401, body: Data(), finalURL: first))
        await client.enqueue(url: audio, response: .init(status: 200, body: Data([255, 0, 128]), finalURL: audio, headers: ["Content-Type": "audio/mpeg"]))
        let service = HttpTTSSource(source: source, client: client, directory: directory)
        do {
            let file = try await service.audio(text: "甲", speed: 10)
            XCTAssertEqual(try Data(contentsOf: file), Data([255, 0, 128]))
        } catch { XCTFail(String(describing: error)) }
    }
}
