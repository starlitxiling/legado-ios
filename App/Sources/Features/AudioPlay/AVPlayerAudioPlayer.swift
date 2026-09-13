import Foundation
import AVFoundation
import MediaPlayer
import Observation
import LegadoCore

@Observable @MainActor
final class AVPlayerAudioPlayer: AudioPlayer {
    var onEvent: ((AudioPlayerEvent) -> Void)?
    private(set) var engine: AudioPlayEngine?
    private(set) var library: MediaBookLibrary?
    private let player = AVPlayer()
    private let owner = UUID()
    private var itemObservers: [NSObjectProtocol] = []
    private var systemObservers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var timer: Timer?
    private var commands: [(MPRemoteCommand, Any)] = []
    private var generation = 0
    private var resumeAfterInterruption = false

    func open(_ library: MediaBookLibrary) {
        if self.library?.book.bookUrl == library.book.bookUrl, engine != nil { return }
        engine?.stop()
        self.library = library
        let engine = AudioPlayEngine(player: self) { [library] index in try await library.audio(index) }
        self.engine = engine
        engine.load(chapterCount: library.chapters.count, chapter: library.initialChapter, position: library.book.durChapterPos)
        engine.progressChanged = { [weak self, library] chapter, position in
            library.record(chapter: chapter, position: position)
            self?.updateNowPlaying()
        }
        engine.stateChanged = { [weak self] in self?.stateChanged() }
        engine.play()
    }

    func prepare(_ resource: MediaResource, position: Int) async throws {
        stop()
        let token = generation
        let asset = AVURLAsset(url: resource.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resource.headers])
        guard try await asset.load(.isPlayable) else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
        let item = AVPlayerItem(asset: asset)
        let event = onEvent
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, self.generation == token, let item, item.status == .failed else { return }
                event?(.failed(item.error?.localizedDescription ?? "音频播放失败"))
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if status == .waitingToPlayAtSpecifiedRate { event?(.buffering) }
                else if status == .playing { event?(.playing) }
            }
        }
        itemObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                event?(.ended)
            }
        })
        itemObservers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                event?(.failed("音频播放中断"))
            }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1000), queue: .main) { [weak self, weak item] time in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                event?(.progress(position: Self.milliseconds(time.seconds), duration: Self.milliseconds(item?.duration.seconds ?? 0)))
                self.engine?.tick()
            }
        }
        if position > 0 {
            await withCheckedContinuation { continuation in
                player.seek(to: CMTime(value: Int64(position), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    continuation.resume()
                }
            }
        }
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
    }

    func play() throws {
        AudioSessionOwnership.claim(owner) { [weak self] in self?.engine?.stop() }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio,
                                options: UserDefaults.standard.bool(forKey: "ignoreAudioFocus") ? [.mixWithOthers] : [])
        try session.setActive(true)
        installControls()
        player.play()
    }

    func pause() { resumeAfterInterruption = false; player.pause() }
    func stop() {
        generation += 1
        resumeAfterInterruption = false
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        statusObservation = nil; playbackObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers = []
        player.replaceCurrentItem(with: nil)
    }
    func seek(to position: Int) { player.seek(to: CMTime(value: Int64(max(0, position)), timescale: 1000)) }

    private static func milliseconds(_ seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds * 1000, Double(Int32.max)))
    }

    private func stateChanged() {
        guard let engine else { return }
        if engine.state == .loading, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.engine?.tick() }
            }
        }
        if engine.state == .stopped || engine.state == .failed {
            timer?.invalidate(); timer = nil
            for (command, target) in commands { command.removeTarget(target) }
            commands = []
            for observer in systemObservers { NotificationCenter.default.removeObserver(observer) }
            systemObservers = []
            if AudioSessionOwnership.isOwner(owner) {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                AudioSessionOwnership.relinquish(owner)
            }
        } else {
            if engine.shouldDeactivateAudioSession, AudioSessionOwnership.isOwner(owner) {
                resumeAfterInterruption = false
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        guard AudioSessionOwnership.isOwner(owner), let engine, let library else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: library.book.name ?? "",
            MPMediaItemPropertyAlbumTitle: library.chapters.indices.contains(engine.chapter) ? library.chapters[engine.chapter].title ?? "" : "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(engine.position) / 1000,
            MPMediaItemPropertyPlaybackDuration: Double(engine.duration) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: engine.state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
    }

    private func installControls() {
        guard commands.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            commands.append((command, target))
        }
        register(center.playCommand) { [weak self] in self?.engine?.play() }
        register(center.pauseCommand) { [weak self] in
            self?.resumeAfterInterruption = false
            self?.engine?.pause()
        }
        register(center.stopCommand) { [weak self] in self?.engine?.stop() }
        register(center.togglePlayPauseCommand) { [weak self] in
            guard let engine = self?.engine else { return }
            if engine.state == .playing || engine.state == .loading { engine.pause() } else { engine.play() }
        }
        register(center.nextTrackCommand) { [weak self] in self?.engine?.next() }
        register(center.previousTrackCommand) { [weak self] in self?.engine?.previous() }
        center.changePlaybackPositionCommand.isEnabled = true
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.engine?.seek(to: Self.milliseconds(position)) }
            return .success
        }
        commands.append((center.changePlaybackPositionCommand, target))
        systemObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    let resume = self.engine?.state == .playing || self.engine?.state == .loading
                    self.engine?.pause(reason: .interruption); self.resumeAfterInterruption = resume
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    let resume = self.resumeAfterInterruption
                    self.resumeAfterInterruption = false
                    if resume, self.engine?.state == .paused, self.engine?.pauseReason == .interruption,
                       AudioSessionOwnership.isOwner(self.owner),
                       AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { self.engine?.play() }
                }
            }
        })
        systemObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.engine?.pause() }
            }
        })
    }
}
