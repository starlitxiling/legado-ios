import Foundation
import AVFoundation
import MediaPlayer
import Observation
import LegadoCore

@Observable @MainActor
final class ReadAloudController {
    let engine = ReadAloudEngine(speaker: SystemSpeaker())
    let preferences = ReadAloudPreferences()
    private(set) var sources: [HttpTTS] = []
    private(set) var errorMessage: String?
    private var httpSpeaker: HttpSpeaker?
    private let work = ReadAloudSessionTasks()
    private var prefetchedPosition: String?
    private var interruption = ReadAloudInterruptionState()
    private var timer: Timer?
    private var commands: [(MPRemoteCommand, Any)] = []
    private var observers: [NSObjectProtocol] = []
    private weak var reader: ReaderViewModel?
    private let database: AppDatabase
    private let client: any HttpClient
    private var title = ""
    private let audioOwner = UUID()
    init(database: AppDatabase, client: any HttpClient) { self.database = database; self.client = client }
    func attach(_ reader: ReaderViewModel) async {
        detach()
        self.reader = reader
        do { sources = try await HttpTTSRepository(database: database).list() }
        catch { errorMessage = error.localizedDescription }
        selectSource(preferences.sourceID)
        engine.progress = { [weak self, weak reader] chapter, range in
            guard let self, let reader else { return }
            reader.followReadAloud(chapter: chapter, range: self.engine.current?.range ?? range, offset: range.location)
            self.title = reader.book?.name ?? reader.chapterTitle
            self.updateNowPlaying()
            if let speaker = self.httpSpeaker {
                let position = "\(chapter):\(self.engine.paragraphIndex):\(self.engine.rate)"
                guard self.prefetchedPosition != position else { return }
                self.prefetchedPosition = position
                let texts = self.engine.paragraphs.dropFirst(self.engine.paragraphIndex + 1).prefix(2).map(\.text)
                let speed = ReadAloudPreferences.httpSpeed(self.engine.rate)
                self.work.start { await speaker.service.prefetch(texts: texts, speed: speed) }
            }
        }
        engine.nextChapter = { [weak reader] in
            guard let reader, reader.chapterPosition + 1 < reader.chapters.count else { return nil }
            let previous = reader.chapterIndex
            await reader.nextChapter()
            guard reader.chapterIndex != previous, let text = reader.pagination?.text.string else {
                throw URLError(.cannotLoadFromNetwork)
            }
            return ReadAloudChapter(index: reader.chapterIndex, text: text, pageRanges: reader.pagination?.pages.map(\.range) ?? [])
        }
        engine.stateChanged = { [weak self] in
            guard let self else { return }
            self.updateNowPlaying()
            if self.engine.state == .stopped {
                self.cancelRound()
                self.interruption.userPaused()
                self.reader?.clearReadAloudHighlight()
                if AudioSessionOwnership.isOwner(self.audioOwner) {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.engine.checkTimer() }
        }
    }
    func selectSource(_ id: Int64?) {
        stop(); cancelRound()
        preferences.sourceID = id
        if let source = sources.first(where: { $0.id == id }) {
            let directory = URL.cachesDirectory.appendingPathComponent("Legado/HttpTTS", isDirectory: true)
            let speaker = HttpSpeaker(service: HttpTTSSource(source: source, client: client, directory: directory,
                database: database, secrets: SourceLoginKeychainStore()), pauseDuration: source.pauseDuration,
                waitForCleanup: { [work] in await work.waitForCancellation() })
            httpSpeaker = speaker; engine.replaceSpeaker(speaker)
        } else { httpSpeaker = nil; engine.replaceSpeaker(SystemSpeaker()) }
    }
    func play() {
        guard !interruption.isInterrupted else { return }
        guard let reader, !reader.isLoading, let text = reader.pagination?.text.string else { return }
        if engine.state == .stopped || engine.chapterIndex != reader.chapterIndex {
            engine.readAloudByPage = preferences.readAloudByPage
            engine.load(text: text, chapter: reader.chapterIndex, offset: reader.characterOffset, pageRanges: reader.pagination?.pages.map(\.range) ?? [])
        }
        do {
            AudioSessionOwnership.claim(audioOwner) { [weak self] in self?.detach() }
            installControls()
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.engine.checkTimer() }
                }
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: UserDefaults.standard.bool(forKey: "ignoreAudioFocus") ? [.mixWithOthers] : [])
            try session.setActive(true)
            engine.rate = preferences.rate; engine.volume = preferences.volume
            engine.play(); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func pause() { interruption.userPaused(); engine.pause() }
    func stop() { interruption.userPaused(); engine.stop() }
    func toggle() { if engine.state == .playing || engine.state == .loading { pause() } else { play() } }
    func nextParagraph() { guard !interruption.isInterrupted else { return }; if engine.state == .stopped { play() }; engine.next() }
    func previousParagraph() { guard !interruption.isInterrupted else { return }; if engine.state == .stopped { play() }; engine.previous() }
    func changePageMode(_ value: Bool) {
        let wasPlaying = engine.state == .playing
        preferences.readAloudByPage = value; stop()
        if wasPlaying { play() }
    }
    func changeRate(_ value: Double) {
        preferences.rate = value; engine.rate = value
        engine.restartCurrent()
    }
    func changeVolume(_ value: Double) {
        preferences.volume = value; engine.volume = value; engine.restartCurrent()
    }
    func detach() {
        cancelRound(); interruption.userPaused()
        engine.stop(); reader?.clearReadAloudHighlight()
        timer?.invalidate(); timer = nil
        for (command, target) in commands { command.removeTarget(target) }
        commands.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if AudioSessionOwnership.isOwner(audioOwner) { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        AudioSessionOwnership.relinquish(audioOwner)
    }
    private func cancelRound() {
        prefetchedPosition = nil
        let service = httpSpeaker?.service
        work.cancelAll { await service?.cancel() }
    }
    private func updateNowPlaying() {
        guard AudioSessionOwnership.isOwner(audioOwner) else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyAlbumTitle: reader?.chapterTitle ?? "",
            MPNowPlayingInfoPropertyPlaybackRate: engine.state == .playing ? engine.rate : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
    }
    private func installControls() {
        guard commands.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            commands.append((command, target))
        }
        register(center.playCommand) { [weak self] in
            guard let self, self.engine.state != .stopped || UserDefaults.standard.bool(forKey: "readAloudByMediaButton") else { return }
            self.play()
        }
        register(center.pauseCommand) { [weak self] in self?.pause() }
        register(center.stopCommand) { [weak self] in self?.stop() }
        register(center.togglePlayPauseCommand) { [weak self] in
            guard let self, self.engine.state != .stopped || UserDefaults.standard.bool(forKey: "readAloudByMediaButton") else { return }
            self.toggle()
        }
        register(center.nextTrackCommand) { [weak self] in self?.nextParagraph() }
        register(center.previousTrackCommand) { [weak self] in self?.previousParagraph() }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.interruption.begin(wasPlaying: self.engine.state == .playing)
                    self.engine.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    let resume = self.interruption.end(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
                    if resume, self.engine.state == .paused { self.play() }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        })
    }
}
