import Foundation

enum JavaHostTime {
    static func format(_ value: Any?, pattern: String, timeZone: TimeZone, offset: Any? = nil) throws -> String {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let number, number.isFinite, number >= -9_223_372_036_854_775_808, number < 9_223_372_036_854_775_808 else {
            throw JsEngineError.exception("timeFormat requires milliseconds in the signed 64-bit range")
        }
        let milliseconds = Int64(number)
        let original = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        var date = original
        var offsetMilliseconds = timeZone.secondsFromGMT(for: original) * 1000
        if let offset {
            let raw = (offset as? NSNumber)?.doubleValue ?? (offset as? String).flatMap(Double.init)
            guard let raw, raw.isFinite, raw >= Double(Int32.min), raw <= Double(Int32.max) else {
                throw JsEngineError.exception("timeFormatUTC requires a signed 32-bit offset in milliseconds")
            }
            offsetMilliseconds = Int(raw)
            date = original.addingTimeInterval(Double(offsetMilliseconds) / 1000)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        let weekday = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        let fractional = ((milliseconds % 1000 + Int64(offset == nil ? 0 : offsetMilliseconds) % 1000) % 1000 + 1000) % 1000
        let characters = Array(pattern)
        var result = "", index = 0, quoted = false
        func padded(_ value: Int64, width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                if index + 1 < characters.count, characters[index + 1] == "'" {
                    result.append(character); index += 2; continue
                }
                quoted.toggle(); index += 1; continue
            }
            if quoted || !character.isASCII || !character.isLetter {
                result.append(character); index += 1; continue
            }
            var end = index + 1
            while end < characters.count, characters[end] == character { end += 1 }
            let width = end - index
            guard "GyYMLwWDdFEuaHkKhmsSzZX".contains(character), character != "X" || width <= 3 else {
                throw JsEngineError.exception("Invalid Java date pattern: \(pattern)")
            }
            switch character {
            case "u": result += padded(Int64(weekday), width: width)
            case "S": result += padded(fractional, width: width)
            case "X", "Z":
                let minutes = abs(offsetMilliseconds / 60_000)
                if character == "X", offsetMilliseconds == 0 { result += "Z" }
                else {
                    let hours = padded(Int64(minutes / 60), width: 2)
                    let minuteText = padded(Int64(minutes % 60), width: 2)
                    let suffix = character == "X" && width == 1 ? "" : (character == "X" && width == 3 ? ":" : "") + minuteText
                    result += (offsetMilliseconds < 0 ? "-" : "+") + hours + suffix
                }
            case "z" where offset != nil: result += "UTC"
            default:
                formatter.dateFormat = String(repeating: String(character), count: width)
                result += formatter.string(from: date)
            }
            index = end
        }
        guard !quoted else { throw JsEngineError.exception("Unterminated quote in Java date pattern: \(pattern)") }
        return result
    }
}
