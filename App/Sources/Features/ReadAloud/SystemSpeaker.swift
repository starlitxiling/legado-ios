import AVFoundation
import LegadoCore

@MainActor
final class SystemSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var progress: ((Int) -> Void)?
    override init() { super.init(); synthesizer.delegate = self }
    func speak(_ text: String, rate: Double, volume: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        speak(text, rate: rate, volume: volume, progress: { _ in }, completion: completion)
    }
    func speak(_ text: String, rate: Double, volume: Double, progress: @escaping (Int) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(rate)))
        utterance.volume = Float(min(1, max(0, volume)))
        self.utterance = utterance; self.completion = completion; self.progress = progress
        synthesizer.speak(utterance)
    }
    func pause() { synthesizer.pauseSpeaking(at: .immediate) }
    func resume() { synthesizer.continueSpeaking() }
    func stop() { completion = nil; progress = nil; utterance = nil; synthesizer.stopSpeaking(at: .immediate) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.progress?(characterRange.location)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            let callback = self.completion; self.completion = nil; self.progress = nil; self.utterance = nil
            callback?(.success(()))
        }
    }
}
