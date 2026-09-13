import Foundation
import Observation

@MainActor
public protocol Speaker: AnyObject {
    func speak(_ text: String, rate: Double, volume: Double, completion: @escaping (Result<Void, Error>) -> Void)
    func speak(_ text: String, rate: Double, volume: Double, progress: @escaping (Int) -> Void, completion: @escaping (Result<Void, Error>) -> Void)
    func pause()
    func resume()
    func stop()
}

public extension Speaker {
    func speak(_ text: String, rate: Double, volume: Double, progress: @escaping (Int) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        progress(0)
        speak(text, rate: rate, volume: volume, completion: completion)
    }
}

public struct ReadAloudChapter: Sendable {
    public let index: Int
    public let text: String
    public let pageRanges: [NSRange]
    public init(index: Int, text: String, pageRanges: [NSRange] = []) { self.index = index; self.text = text; self.pageRanges = pageRanges }
}

public struct ReadAloudParagraph: Equatable, Sendable {
    public let text: String
    public let range: NSRange
    public static func split(_ text: String, pageRanges: [NSRange] = []) -> [Self] {
        let string = text as NSString
        var result: [Self] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { value, range, _, _ in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let boundaries = pageRanges.map(\.location).filter { $0 > range.location && $0 < NSMaxRange(range) }.sorted()
            let starts = [range.location] + boundaries + [NSMaxRange(range)]
            for (start, end) in zip(starts, starts.dropFirst()) where end > start {
                let part = NSRange(location: start, length: end - start)
                result.append(Self(text: string.substring(with: part), range: part))
            }
        }
        return result
    }
}

@Observable @MainActor
public final class ReadAloudEngine {
    public enum State: Equatable { case stopped, playing, paused, loading }
    public private(set) var state: State = .stopped
    public private(set) var paragraphs: [ReadAloudParagraph] = []
    public private(set) var paragraphIndex = 0
    public private(set) var chapterIndex = 0
    public private(set) var characterOffset = 0
    public private(set) var errorMessage: String?
    public private(set) var remainingSeconds: TimeInterval?
    public var stopAt: Date? { guard state == .playing, let remainingSeconds else { return nil }; return (activeSince ?? now()).addingTimeInterval(remainingSeconds) }
    public var readAloudByPage = false
    public var rate: Double = 1
    public var volume: Double = 1
    public var progress: ((Int, NSRange) -> Void)?
    public var stateChanged: (() -> Void)?
    public var nextChapter: (() async throws -> ReadAloudChapter?)?
    private var speaker: any Speaker
    private let now: () -> Date
    private var activeSince: Date?
    private var speechStarted = false
    private var completedWhilePaused = false
    private var generation = UUID()
    private var chapterTask: Task<Void, Never>?
    public init(speaker: any Speaker, now: @escaping () -> Date = Date.init) { self.speaker = speaker; self.now = now }
    public var current: ReadAloudParagraph? { paragraphs.indices.contains(paragraphIndex) ? paragraphs[paragraphIndex] : nil }
    public func replaceSpeaker(_ speaker: any Speaker) { stop(); self.speaker = speaker }
    public func load(text: String, chapter: Int, offset: Int = 0, pageRanges: [NSRange] = []) {
        settleTimer()
        let remaining = remainingSeconds
        stop(); remainingSeconds = remaining
        paragraphs = ReadAloudParagraph.split(text, pageRanges: readAloudByPage ? pageRanges : [])
        chapterIndex = chapter
        paragraphIndex = paragraphs.lastIndex(where: { $0.range.location <= offset }) ?? 0
        if let current {
            let local = min(max(0, offset - current.range.location), max(0, current.range.length - 1))
            characterOffset = current.range.location + (current.text as NSString).rangeOfComposedCharacterSequence(at: local).location
        } else { characterOffset = 0 }
    }
    public func play() {
        checkTimer()
        guard current != nil, state != .playing, state != .loading else { return }
        if state == .paused {
            state = .playing
            if completedWhilePaused { completedWhilePaused = false; advance(); return }
            if speechStarted { activeSince = now() }
            speaker.resume(); stateChanged?()
        } else { speakCurrent() }
    }
    public func pause() {
        if state == .loading { stop(); return }
        guard state == .playing else { return }
        settleTimer(); state = .paused; speaker.pause(); stateChanged?()
    }
    public func stop() {
        generation = UUID(); chapterTask?.cancel(); chapterTask = nil
        speaker.stop(); state = .stopped; remainingSeconds = nil; activeSince = nil
        speechStarted = false; completedWhilePaused = false; errorMessage = nil; stateChanged?()
    }
    public func next() { advance() }
    public func restartCurrent() { if state == .playing { speakCurrent() } }
    public func previous() {
        guard paragraphIndex > 0 else { return }
        paragraphIndex -= 1; characterOffset = current?.range.location ?? 0; speakCurrent()
    }
    public func setTimer(seconds: TimeInterval?) {
        remainingSeconds = seconds.map { max(0, $0) }
        activeSince = state == .playing && speechStarted ? now() : nil
        checkTimer()
    }
    public func checkTimer() {
        let wasActive = activeSince != nil
        settleTimer()
        if let remainingSeconds, remainingSeconds <= 0 { stop(); return }
        if wasActive, state == .playing { activeSince = now() }
    }
    private func settleTimer() {
        if let start = activeSince, let remainingSeconds { self.remainingSeconds = max(0, remainingSeconds - max(0, now().timeIntervalSince(start))) }
        activeSince = nil
    }
    private func speakCurrent() {
        settleTimer()
        if let remainingSeconds, remainingSeconds <= 0 { stop(); return }
        guard let current else { stop(); return }
        generation = UUID(); chapterTask?.cancel(); chapterTask = nil; speaker.stop()
        let token = generation
        let start = max(current.range.location, min(characterOffset, NSMaxRange(current.range) - 1))
        let suffix = (current.text as NSString).substring(from: start - current.range.location)
        characterOffset = start; speechStarted = false; completedWhilePaused = false
        state = .playing; errorMessage = nil
        progress?(chapterIndex, NSRange(location: start, length: NSMaxRange(current.range) - start)); stateChanged?()
        speaker.speak(suffix, rate: rate, volume: volume, progress: { [weak self] offset in
            guard let self, self.generation == token, self.state == .playing else { return }
            if !self.speechStarted { self.speechStarted = true; self.activeSince = self.now() }
            let local = min(max(0, offset), max(0, (suffix as NSString).length - 1))
            let position = start + (suffix as NSString).rangeOfComposedCharacterSequence(at: local).location
            guard position >= self.characterOffset else { return }
            self.characterOffset = position
            self.progress?(self.chapterIndex, NSRange(location: position, length: NSMaxRange(current.range) - position))
        }, completion: { [weak self] result in
            guard let self, self.generation == token, self.state == .playing || self.state == .paused else { return }
            self.settleTimer()
            switch result {
            case .success:
                if self.state == .paused { self.completedWhilePaused = true }
                else { self.advance() }
            case .failure(let error):
                self.stop(); self.errorMessage = error.localizedDescription; self.stateChanged?()
            }
        })
    }
    private func advance() {
        settleTimer()
        if let remainingSeconds, remainingSeconds <= 0 { stop(); return }
        guard current != nil else { return }
        if paragraphIndex + 1 < paragraphs.count {
            paragraphIndex += 1; characterOffset = current?.range.location ?? 0; speakCurrent(); return
        }
        generation = UUID(); speaker.stop(); chapterTask?.cancel()
        let token = generation
        guard let nextChapter else { stop(); return }
        state = .loading; stateChanged?()
        chapterTask = Task { [weak self] in
            do {
                let next = try await nextChapter()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                guard let next else { self.stop(); return }
                self.paragraphs = ReadAloudParagraph.split(next.text, pageRanges: self.readAloudByPage ? next.pageRanges : [])
                self.chapterIndex = next.index; self.paragraphIndex = 0; self.characterOffset = self.current?.range.location ?? 0
                self.speakCurrent()
            } catch {
                guard let self, self.generation == token else { return }
                self.stop(); self.errorMessage = error.localizedDescription; self.stateChanged?()
            }
        }
    }
}
