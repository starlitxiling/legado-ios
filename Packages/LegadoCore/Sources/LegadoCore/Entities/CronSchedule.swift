import Foundation

public struct CronSchedule: Sendable {
    private let fields: [Set<Int>]
    private let dayAndWeek: Bool

    public init(_ expression: String) throws {
        let parts = expression.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 5 else { throw JsEngineError.exception("Cron requires five fields") }
        let ranges = [0...59,0...23,1...31,1...12,0...7]
        fields = try zip(parts,ranges).enumerated().map { index, pair in
            let (text, bounds) = pair
            var values = Set<Int>()
            for segment in text.split(separator: ",", omittingEmptySubsequences: false) {
                let steps = segment.split(separator: "/", omittingEmptySubsequences: false)
                guard (1...2).contains(steps.count), let step = steps.count == 2 ? Int(steps[1]) : 1, step > 0 else { throw JsEngineError.exception("Invalid cron step") }
                let range: ClosedRange<Int>
                if steps[0] == "*" { range = bounds }
                else {
                    let limits = steps[0].split(separator: "-", omittingEmptySubsequences: false)
                    guard (1...2).contains(limits.count), let first = Int(limits[0]), bounds.contains(first) else { throw JsEngineError.exception("Invalid cron value") }
                    let last = limits.count == 2 ? Int(limits[1]) : steps.count == 2 ? bounds.upperBound : first
                    guard let last, bounds.contains(last), last >= first else { throw JsEngineError.exception("Invalid cron range") }
                    range = first...last
                }
                for value in stride(from: range.lowerBound, through: range.upperBound, by: step) { values.insert(index == 4 && value == 7 ? 0 : value) }
            }
            return values
        }
        dayAndWeek = parts[2].hasPrefix("*") || parts[4].hasPrefix("*")
    }

    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        let threshold = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60 + 60)
        var day = calendar.startOfDay(for: threshold)
        for _ in 0..<(8*366) {
            let parts = calendar.dateComponents([.month,.day,.weekday], from: day)
            let dom = fields[2].contains(parts.day ?? 0), dow = fields[4].contains((parts.weekday ?? 1)-1)
            if fields[3].contains(parts.month ?? 0), dayAndWeek ? dom && dow : dom || dow {
                var result: Date?
                for hour in fields[1].sorted() { for minute in fields[0].sorted() {
                    for repeated: Calendar.RepeatedTimePolicy in [.first,.last] {
                        if let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                            matchingPolicy: .strict, repeatedTimePolicy: repeated, direction: .forward),
                           calendar.isDate(candidate, inSameDayAs: day), candidate >= threshold,
                           result == nil || candidate < result! { result = candidate }
                    }
                } }
                if let result { return result }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    public static func isDue(_ rule: AutoTaskRule, at date: Date, calendar: Calendar = .current) -> Bool {
        guard rule.enable, let schedule = try? CronSchedule(rule.cron ?? "") else { return false }
        let base = rule.lastRunAt > 0 ? Date(timeIntervalSince1970: Double(rule.lastRunAt)/1000) : date.addingTimeInterval(-300)
        return schedule.next(after: base, calendar: calendar).map { $0 <= date } ?? false
    }
}
