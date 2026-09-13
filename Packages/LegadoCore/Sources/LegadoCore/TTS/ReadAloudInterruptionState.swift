public struct ReadAloudInterruptionState {
    public private(set) var isInterrupted = false
    private var resumeWhenEnded = false
    public init() {}
    public mutating func begin(wasPlaying: Bool) {
        guard !isInterrupted else { return }
        isInterrupted = true; resumeWhenEnded = wasPlaying
    }
    public mutating func userPaused() { resumeWhenEnded = false }
    public mutating func end(shouldResume: Bool) -> Bool {
        let resume = isInterrupted && resumeWhenEnded && shouldResume
        isInterrupted = false; resumeWhenEnded = false
        return resume
    }
}
