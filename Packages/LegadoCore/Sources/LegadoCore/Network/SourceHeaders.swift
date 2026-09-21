import Foundation

public enum SourceHeaders {
    public static func parse(_ text: String) throws -> [String: String] {
        let input = Array(text)
        var normalized = "", index = 0, quote: Character?, escaped = false, keyExpected = false
        while index < input.count {
            let character = input[index]
            if let active = quote {
                normalized.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == active { quote = nil }
                index += 1; continue
            }
            if character == "/", index + 1 < input.count, input[index + 1] == "/" || input[index + 1] == "*" {
                let start = index, line = input[index + 1] == "/"
                index += 2
                while index < input.count {
                    if line && input[index] == "\n" { break }
                    if !line && index + 1 < input.count && input[index] == "*" && input[index + 1] == "/" { index += 2; break }
                    index += 1
                }
                normalized += String(input[start..<index]); continue
            }
            if character == "\"" || character == "'" {
                quote = character; keyExpected = false; normalized.append(character); index += 1; continue
            }
            if keyExpected && !character.isWhitespace && character != "}" && character != "/" {
                let start = index
                while index < input.count && input[index] != ":" { index += 1 }
                guard index < input.count else { throw JsEngineError.exception("Header key is missing a colon") }
                let key = String(input[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                normalized += String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
                keyExpected = false; continue
            }
            normalized.append(character)
            if character == "{" || character == "," { keyExpected = true }
            else if character == ":" { keyExpected = false }
            index += 1
        }
        let decoder = JSONDecoder(); decoder.allowsJSON5 = true
        let values = try decoder.decode([String: HeaderValue].self, from: Data(normalized.utf8))
        return values.compactMapValues { $0.text }
    }

    private struct HeaderValue: Decodable {
        let text: String?
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { text = nil }
            else if let string = try? value.decode(String.self) { text = string }
            else if let boolean = try? value.decode(Bool.self) { text = String(boolean) }
            else if let number = try? value.decode(Int64.self) { text = String(number) }
            else { text = String(try value.decode(Double.self)) }
        }
    }
}
