import Foundation

extension Book {
    public func simulatedTotalChapterNum(on today: KotlinLocalDate) -> Int {
        guard let config = readConfig, config.readSimulating else { return totalChapterNum }
        let start = config.startDate ?? today
        let months = (today.year - start.year) * 12 + today.month - start.month
        var days = today.day - start.day
        func monthLength(_ year: Int, _ month: Int) -> Int {
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        }
        // Kotlin uses Period.between(...).days, excluding complete months and years.
        if months > 0 && days < 0 {
            let month = today.month == 1 ? 12 : today.month - 1
            let year = today.month == 1 ? today.year - 1 : today.year
            let length = monthLength(year, month)
            days = length - min(start.day, length) + today.day
        } else if months < 0 && days > 0 { days -= monthLength(today.year, today.month) }
        let count = Int32(truncatingIfNeeded: config.startChapter ?? 0)
            &+ (Int32(days + 1) &* Int32(truncatingIfNeeded: config.dailyChapters))
        return min(totalChapterNum, max(0, Int(count)))
    }

    public func simulatedTotalChapterNum(now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let date = KotlinLocalDate(year: year, month: month, day: day) else { return totalChapterNum }
        return simulatedTotalChapterNum(on: date)
    }
}
