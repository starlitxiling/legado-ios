import AVFoundation
import LegadoCore

@MainActor
final class HttpSpeaker: NSObject, Speaker, AVAudioPlayerDelegate {
    let service: HttpTTSSource
    private let pauseDuration: Int
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private var playback: CheckedContinuation<Void, Error>?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var progress: ((Int) -> Void)?
    private var progressTimer: Timer?
    private var textLength = 0
    private var paused = false
    private var generation = UUID()
    private let waitForCleanup: @MainActor () async -> Void
    init(service: HttpTTSSource, pauseDuration: Int, waitForCleanup: @escaping @MainActor () async -> Void = {}) {
        self.service = service; self.pauseDuration = min(10_000, max(0, pauseDuration)); self.waitForCleanup = waitForCleanup
    }
    func speak(_ text: String, rate: Double, volume: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        speak(text, rate: rate, volume: volume, progress: { _ in }, completion: completion)
    }
    func speak(_ text: String, rate: Double, volume: Double, progress: @escaping (Int) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        stop(); self.completion = completion; self.progress = progress; textLength = (text as NSString).length
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                await self.waitForCleanup()
                try Task.checkCancellation()
                try await self.service.withAudio(text: text, speed: ReadAloudPreferences.httpSpeed(rate), maximumRecompositions: 2) { url in
                    try await self.playAudio(url, volume: volume, token: token)
                }
                if self.pauseDuration > 0 { try await Task.sleep(nanoseconds: UInt64(self.pauseDuration) * 1_000_000) }
                while self.paused { try await Task.sleep(nanoseconds: 100_000_000) }
                guard token == self.generation, !Task.isCancelled else { return }
                self.finish(.success(()))
            } catch {
                guard token == self.generation, !Task.isCancelled else { return }
                self.finish(.failure(error))
            }
        }
    }
    private func playAudio(_ url: URL, volume: Double, token: UUID) async throws {
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self; player.volume = Float(min(1, max(0, volume)))
        self.player = player
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            playback = continuation
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.reportProgress() }
            }
            if !paused {
                if player.play() { reportProgress() }
                else { completePlayback(.failure(URLError(.cannotDecodeContentData))) }
            }
        }
    }
    private func reportProgress() {
        guard !paused, let player, player.isPlaying, player.duration.isFinite, player.duration > 0 else { return }
        progress?(ReadAloudPlaybackProgress.offset(currentTime: player.currentTime, duration: player.duration, textLength: textLength))
    }
    func pause() { paused = true; player?.pause() }
    func resume() {
        paused = false
        if let player {
            if player.play() { reportProgress() }
            else { completePlayback(.failure(URLError(.cannotDecodeContentData))) }
        }
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil; completion = nil; progress = nil
        completePlayback(.failure(CancellationError())); paused = false
    }
    private func completePlayback(_ result: Result<Void, Error>) {
        progressTimer?.invalidate(); progressTimer = nil
        player?.stop(); player = nil
        let continuation = playback; playback = nil; continuation?.resume(with: result)
    }
    private func finish(_ result: Result<Void, Error>) {
        let callback = completion; completion = nil; progress = nil; callback?(result)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.completePlayback(flag ? .success(()) : .failure(URLError(.cannotDecodeContentData)))
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.completePlayback(.failure(error ?? URLError(.cannotDecodeContentData)))
        }
    }
}
