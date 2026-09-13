import Foundation

enum CoverTypography {
    static func columns(_ text: String, capacity: Int) -> [String] {
        let characters = Array(text)
        let count = max(1, capacity)
        return stride(from: 0, to: characters.count, by: count).map {
            String(characters[$0..<min($0 + count, characters.count)])
        }
    }
    static func size(width: Double, divisor: Double, large: Int, small: Int, custom: Bool,
                     fits: (Double) -> Bool) -> Double {
        let initial = width / divisor * (custom ? Double(max(50, min(200, large))) / 100 : 1)
        guard !fits(initial) else { return initial }
        return custom ? width / divisor * Double(max(50, min(200, small))) / 100
            : width / (divisor == 7 ? 9 : 16)
    }
}
