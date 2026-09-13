import Foundation
import Observation

public enum AudioPlayerEvent {
    case progress(position: Int, duration: Int)
    case buffering, playing, ended
    case failed(String)
}

@MainActor public protocol AudioPlayer: AnyObject {
    var onEvent: ((AudioPlayerEvent) -> Void)? { get set }
    func prepare(_ resource: MediaResource, position: Int) async throws
    func play() throws
    func pause()
    func stop()
    func seek(to position: Int)
}

@Observable @MainActor public final class AudioPlayEngine {
    public enum State: Equatable { case stopped, loading, playing, paused, failed }
    public enum PauseReason: Equatable { case user, interruption }
    public private(set) var pauseReason: PauseReason?
    public var shouldDeactivateAudioSession: Bool {
        state == .stopped || state == .failed || (state == .paused && pauseReason == .user)
    }
    public private(set) var state: State = .stopped
    public private(set) var chapter = 0
    public private(set) var chapterCount = 0
    /// 与 Kotlin durChapterPos 一致，音频进度单位为毫秒。
    public private(set) var position = 0
    public private(set) var duration = 0
    public private(set) var retryCount = 0
    public private(set) var errorMessage: String?
    public private(set) var timerDeadline: TimeInterval?
    public var progressChanged: ((Int, Int) -> Void)?
    public var stateChanged: (() -> Void)?
    private let player: any AudioPlayer
    private let resolve: (Int) async throws -> MediaResource
    private let now: () -> TimeInterval
    private let maximumRetries: Int
    private let timeout: TimeInterval
    private var generation = 0
    private var work: Task<Void, Never>?
    private var loadingSince: TimeInterval?
    private var prepared = false

    public init(player: any AudioPlayer, maximumRetries: Int = 2, timeout: TimeInterval = 60,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                resolve: @escaping (Int) async throws -> MediaResource) {
        self.player = player; self.resolve = resolve; self.now = now
        self.maximumRetries = max(0, maximumRetries); self.timeout = max(1, timeout)
    }

    public func load(chapterCount: Int, chapter: Int = 0, position: Int = 0) {
        stop()
        self.chapterCount = max(0, chapterCount)
        self.chapter = min(max(0, chapter), max(0, chapterCount - 1))
        self.position = max(0, position); duration = 0; retryCount = 0; errorMessage = nil
    }

    public func play() {
        guard chapterCount > 0, state != .playing, state != .loading else { return }
        retryCount = 0; errorMessage = nil
        pauseReason = nil
        if prepared {
            do { try player.play(); transition(.playing) }
            catch { fail(error.localizedDescription) }
        } else { start() }
    }

    public func pause() { pause(reason: .user) }

    public func pause(reason: PauseReason) {
        if state == .paused {
            if reason == .user { pauseReason = .user; stateChanged?() }
            return
        }
        guard state == .playing || state == .loading else { return }
        pauseReason = reason
        if state == .loading { cancel(); prepared = false; player.stop() }
        else { player.pause() }
        loadingSince = nil; transition(.paused); save()
    }

    public func stop() {
        pauseReason = nil
        cancel(); player.stop(); prepared = false; loadingSince = nil; timerDeadline = nil
        transition(.stopped); save()
    }

    public func seek(to value: Int) {
        position = min(max(0, value), duration > 0 ? duration : Int.max)
        if prepared { player.seek(to: position) }
        save()
    }

    public func next() { select(chapter + 1) }
    public func previous() { select(chapter - 1) }
    public func select(_ index: Int) {
        guard (0..<chapterCount).contains(index) else { return }
        save(); cancel(); player.stop(); prepared = false
        chapter = index; position = 0; duration = 0; retryCount = 0; errorMessage = nil
        save(); start()
    }

    public func setTimer(seconds: TimeInterval?) {
        timerDeadline = seconds.flatMap { $0.isFinite && $0 > 0 ? now() + $0 : nil }
    }

    public func tick() {
        if let timerDeadline, now() >= timerDeadline { stop(); return }
        if let loadingSince, now() - loadingSince >= timeout { fail("音频加载超时") }
    }

    public func waitUntilSettled() async { await work?.value }

    private func start() {
        pauseReason = nil
        cancel(); prepared = false; player.stop()
        loadingSince = now(); transition(.loading)
        let token = generation
        let index = chapter
        player.onEvent = { [weak self] event in
            guard let self, self.generation == token else { return }
            self.receive(event)
        }
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let resource = try await self.resolve(index)
                guard !Task.isCancelled, self.generation == token else { return }
                try await self.player.prepare(resource, position: self.position)
                guard !Task.isCancelled, self.generation == token else { return }
                self.prepared = true
                try self.player.play()
                self.loadingSince = nil; self.transition(.playing)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func receive(_ event: AudioPlayerEvent) {
        switch event {
        case let .progress(value, total):
            guard prepared else { return }
            position = max(0, value); duration = max(0, total); save()
        case .buffering:
            guard state == .playing else { return }
            loadingSince = now(); transition(.loading)
        case .playing:
            guard state == .loading, prepared else { return }
            loadingSince = nil; transition(.playing)
        case .ended:
            guard state == .playing || state == .loading else { return }
            if chapter + 1 < chapterCount { next() } else { stop() }
        case .failed(let message):
            guard state == .playing || state == .loading else { return }
            fail(message)
        }
    }

    private func fail(_ message: String) {
        cancel(); player.stop(); prepared = false; loadingSince = nil; save()
        if retryCount < maximumRetries { retryCount += 1; start() }
        else { errorMessage = message; transition(.failed) }
    }

    private func cancel() {
        generation += 1; work?.cancel(); work = nil; player.onEvent = nil
    }
    private func save() { if chapterCount > 0 { progressChanged?(chapter, position) } }
    private func transition(_ value: State) { state = value; stateChanged?() }
}
