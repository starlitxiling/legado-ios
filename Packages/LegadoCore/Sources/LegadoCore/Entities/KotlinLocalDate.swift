import Foundation

/// 不依赖时区的公历日期；对应 GsonExtensions.kt:247 的 LocalDate 适配器。
public struct KotlinLocalDate: Codable, Equatable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (-999999999...999999999).contains(year), (1...12).contains(month) else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    static func parse(_ value: GsonValue) -> KotlinLocalDate? {
        switch value {
        case let .string(text):
            guard text.range(of: #"^[+-]?[0-9]{4,9}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
            let negative = text.hasPrefix("-")
            let positive = text.hasPrefix("+")
            let unsigned = negative || positive ? String(text.dropFirst()) : text
            let parts = unsigned.split(separator: "-")
            guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
                  !(negative && year == 0), !(positive && parts[0].count == 4),
                  !(!negative && !positive && parts[0].count > 4) else { return nil }
            return KotlinLocalDate(year: negative ? -year : year, month: month, day: day)
        case .object:
            guard let year = value["year"]?.numericText.flatMap(Int32.init),
                  let month = value["month"]?.numericText.flatMap(Int32.init),
                  let day = value["day"]?.numericText.flatMap(Int32.init) else { return nil }
            return KotlinLocalDate(year: Int(year), month: Int(month), day: Int(day))
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        guard let value = Self.parse(try GsonValue(from: decoder)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "无效 LocalDate"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        let magnitude = String(abs(year))
        let digits = String(repeating: "0", count: max(0, 4 - magnitude.count)) + magnitude
        let yearText = (year < 0 ? "-" : year > 9999 ? "+" : "") + digits
        let monthText = month < 10 ? "0\(month)" : String(month)
        let dayText = day < 10 ? "0\(day)" : String(day)
        var container = encoder.singleValueContainer()
        try container.encode("\(yearText)-\(monthText)-\(dayText)")
    }
}
