import Foundation

public enum ReadAloudPlaybackProgress {
    public static func offset(currentTime: TimeInterval, duration: TimeInterval, textLength: Int) -> Int {
        guard currentTime.isFinite, duration.isFinite, duration > 0, textLength > 0 else { return 0 }
        return min(textLength - 1, Int((min(1, max(0, currentTime / duration)) * Double(textLength)).rounded(.down)))
    }
}
