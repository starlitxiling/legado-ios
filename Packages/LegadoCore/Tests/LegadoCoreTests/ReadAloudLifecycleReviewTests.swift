import XCTest
@testable import LegadoCore

@MainActor
final class ReadAloudLifecycleReviewTests: XCTestCase {
    final class ProgressSpeaker: Speaker {
        var report: ((Int) -> Void)?
        var completion: ((Result<Void, Error>) -> Void)?
        var texts: [String] = []
        func speak(_ text: String, rate: Double, volume: Double, completion: @escaping (Result<Void, Error>) -> Void) { texts.append(text); self.completion = completion }
        func speak(_ text: String, rate: Double, volume: Double, progress: @escaping (Int) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
            speak(text, rate: rate, volume: volume, completion: completion); report = progress
        }
        func pause() {}
        func resume() {}
        func stop() {}
    }
    func test4ProgressAndPageSegments() {
        let speaker = ProgressSpeaker(), engine = ReadAloudEngine(speaker: ProgressSpeaker())
        engine.replaceSpeaker(speaker); engine.readAloudByPage = true
        var offsets: [Int] = []
        engine.progress = { _, range in offsets.append(range.location) }
        engine.load(text: "甲乙丙丁戊己", chapter: 0, offset: 1, pageRanges: [NSRange(location: 0, length: 3), NSRange(location: 3, length: 3)])
        engine.play(); XCTAssertEqual(speaker.texts.last, "乙丙")
        speaker.report?(1); XCTAssertEqual(offsets.last, 2)
        let stale = speaker.report
        speaker.completion?(.success(())); XCTAssertEqual(speaker.texts.last, "丁戊己")
        stale?(0); XCTAssertEqual(offsets.last, 3)
        speaker.report?(2); XCTAssertEqual(offsets.last, 5)
    }
    func test6InterruptionOnlyResumesAutomaticPause() {
        var state = ReadAloudInterruptionState()
        state.begin(wasPlaying: true); XCTAssertTrue(state.end(shouldResume: true))
        state.begin(wasPlaying: false); XCTAssertFalse(state.end(shouldResume: true))
        state.begin(wasPlaying: true); state.userPaused(); XCTAssertFalse(state.end(shouldResume: true))
        state.begin(wasPlaying: true); XCTAssertFalse(state.end(shouldResume: false))
        XCTAssertFalse(state.end(shouldResume: true))
    }
    func test4HTTPPositionEstimateIsBounded() {
        XCTAssertEqual(ReadAloudPlaybackProgress.offset(currentTime: 5, duration: 10, textLength: 100), 50)
        XCTAssertEqual(ReadAloudPlaybackProgress.offset(currentTime: 20, duration: 10, textLength: 100), 99)
        XCTAssertEqual(ReadAloudPlaybackProgress.offset(currentTime: 5, duration: 0, textLength: 100), 0)
        XCTAssertEqual(ReadAloudPlaybackProgress.offset(currentTime: .nan, duration: 10, textLength: 100), 0)
    }
    func test7DecodeFailureEvictsAndRecomposesWithBound() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: "https://tts.test/decode")!
        for byte: UInt8 in [1, 2, 3] { await client.enqueue(url: url, response: .init(status: 200, body: Data([byte]), finalURL: url)) }
        let service = HttpTTSSource(source: .init(id: 7, name: "decode", url: url.absoluteString), client: client, directory: directory)
        do {
            try await service.withAudio(text: "甲", speed: 10, maximumRecompositions: 2) { _ in throw URLError(.cannotDecodeContentData) }
            XCTFail("必须有界失败")
        } catch { XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData) }
        let count = await client.requests.count; XCTAssertEqual(count, 3)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }
    actor GateClient: HttpClient {
        var waiters: [CheckedContinuation<HttpResponse, Error>] = []
        func send(_ request: HttpRequest) async throws -> HttpResponse {
            try await withCheckedThrowingContinuation { waiters.append($0) }
        }
        func ready(_ count: Int = 1) -> Bool { waiters.count == count }
        func release() {
            for waiter in waiters { waiter.resume(returning: .init(status: 200, body: Data([1]), finalURL: URL(string: "https://tts.test/gate")!)) }
            waiters.removeAll()
        }
    }
    func test8CancelRoundRejectsLateDownloadAndAllPrefetch() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = GateClient()
        let service = HttpTTSSource(source: .init(id: 8, name: "gate", url: "https://tts.test/gate"), client: client, directory: directory)
        let task = Task { try await service.audio(text: "甲", speed: 10) }
        let prefetch = Task { await service.prefetch(texts: ["乙", "丙"], speed: 10) }
        while !(await client.ready(3)) { await Task.yield() }
        await service.cancel()
        let pending = await service.pendingCount
        XCTAssertEqual(pending, 0)
        await client.release()
        do { _ = try await task.value; XCTFail("旧轮次不得写缓存") } catch is CancellationError {}
        await prefetch.value
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }
    func test9CapacityExpiryAndPinnedPlayback() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: "https://tts.test/cache")!
        for _ in 0..<4 { await client.enqueue(url: url, response: .init(status: 200, body: Data([1, 2]), finalURL: url)) }
        let clock = TestClock()
        let service = HttpTTSSource(source: .init(id: 9, name: "cache", url: url.absoluteString), client: client, directory: directory,
            maximumCacheBytes: 4, maximumCacheAge: 10, now: { clock.date })
        let first = try await service.audio(text: "甲", speed: 10)
        clock.date = Date(timeIntervalSince1970: 1)
        let second = try await service.audio(text: "乙", speed: 10)
        clock.date = Date(timeIntervalSince1970: 2)
        _ = try await service.audio(text: "丙", speed: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        try await service.withAudio(text: "乙", speed: 10) { pinned in
            clock.date = Date(timeIntervalSince1970: 20)
            try await service.trimCache()
            XCTAssertTrue(FileManager.default.fileExists(atPath: pinned.path))
        }
        try await service.trimCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }
    final class TestClock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 0) }
    func test9ExpiredFileIsNotRepinnedBeforeEviction() async throws {
        let directory = testDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = ReplayHttpClient(), url = URL(string: "https://tts.test/expired")!, clock = TestClock()
        await client.enqueue(url: url, response: .init(status: 200, body: Data([1]), finalURL: url))
        await client.enqueue(url: url, response: .init(status: 200, body: Data([2]), finalURL: url))
        let service = HttpTTSSource(source: .init(id: 99, name: "expiry", url: url.absoluteString), client: client, directory: directory,
            maximumCacheAge: 10, now: { clock.date })
        _ = try await service.audio(text: "甲", speed: 10)
        clock.date = Date(timeIntervalSince1970: 11)
        try await service.withAudio(text: "甲", speed: 10) { file in XCTAssertEqual(try Data(contentsOf: file), Data([2])) }
        let count = await client.requests.count; XCTAssertEqual(count, 2)
    }
    private func testDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/tts-review-\(UUID())")
    }
}
