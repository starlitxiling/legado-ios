import Foundation

enum JavaHostEncoding {
    static func bytes(_ value: Any?) throws -> Data {
        if let data = value as? Data { return data }
        guard let values = value as? [Any] else { throw JsEngineError.exception("Expected a byte array") }
        return try Data(values.map { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  (-128...255).contains(number.intValue) else {
                throw JsEngineError.exception("Byte array elements must be integers between -128 and 255")
            }
            return UInt8(truncatingIfNeeded: number.intValue)
        })
    }

    static func charset(_ name: String) throws -> String.Encoding {
        switch name.uppercased() {
        case "UTF-8", "UTF8": return .utf8
        case "UTF-16", "UTF16": return .utf16
        case "UTF-16LE", "UTF16LE": return .utf16LittleEndian
        case "UTF-16BE", "UTF16BE": return .utf16BigEndian
        default:
            do { return try ResponseDecoder.encoding(for: name) }
            catch { throw JsEngineError.exception("Unsupported charset: \(name)") }
        }
    }

    static func encode(_ value: String, charset name: String = "UTF-8") throws -> Data {
        let encoding = try charset(name)
        if value.isEmpty { return Data() }
        if encoding == .utf16 {
            guard let bytes = value.data(using: .utf16BigEndian) else {
                throw JsEngineError.exception("Cannot encode text using UTF-16")
            }
            return Data([0xfe, 0xff]) + bytes
        }
        if let data = value.data(using: encoding) { return data }
        var data = Data()
        for scalar in value.unicodeScalars {
            data.append(String(scalar).data(using: encoding) ?? Data([0x3f]))
        }
        return data
    }

    static func decode(_ data: Data, charset name: String = "UTF-8") throws -> String {
        let encoding = try charset(name)
        if encoding == .utf8 { return String(decoding: data, as: UTF8.self) }
        if encoding == .ascii { return data.map { $0 < 128 ? String(UnicodeScalar($0)) : "\u{fffd}" }.joined() }
        if [.utf16, .utf16BigEndian, .utf16LittleEndian].contains(encoding) {
            var bytes = Array(data)
            var little = encoding == .utf16LittleEndian
            if encoding == .utf16 {
                if bytes.starts(with: [0xff, 0xfe]) { little = true; bytes.removeFirst(2) }
                else if bytes.starts(with: [0xfe, 0xff]) { bytes.removeFirst(2) }
            }
            var units: [UInt16] = []
            for index in stride(from: 0, to: bytes.count, by: 2) {
                guard index + 1 < bytes.count else { units.append(0xfffd); break }
                units.append(little ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                                   : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
            }
            return String(decoding: units, as: UTF16.self)
        }
        guard let text = String(data: data, encoding: encoding) else {
            throw JsEngineError.exception("Invalid byte sequence for charset \(name)")
        }
        return text
    }

    static func hex(_ value: String) throws -> Data {
        var digits = Array(value.filter { !$0.isWhitespace })
        if digits.count % 2 != 0 { digits.insert("0", at: 0) }
        return try Data(stride(from: 0, to: digits.count, by: 2).map {
            guard let high = hexDigit(digits[$0]), let low = hexDigit(digits[$0 + 1]) else {
                throw JsEngineError.exception("Invalid hexadecimal input")
            }
            return high << 4 | low
        })
    }

    private static func hexDigit(_ character: Character) -> UInt8? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 65...70: return UInt8(scalar.value - 55)
        case 97...102: return UInt8(scalar.value - 87)
        case 0xff21...0xff26: return UInt8(scalar.value - 0xff21 + 10)
        case 0xff41...0xff46: return UInt8(scalar.value - 0xff41 + 10)
        default:
            guard scalar.value <= 0xffff, scalar.properties.numericType == .decimal,
                  let digit = character.wholeNumberValue, digit < 10 else { return nil }
            return UInt8(digit)
        }
    }

    static func base64(_ value: String, flags: Int) throws -> Data {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789=" + (flags & 8 != 0 ? "-_" : "+/"))
        var text = value.filter { alphabet.contains($0) }
        if let padding = text.firstIndex(of: "=") {
            let count = text.distance(from: text.startIndex, to: padding)
            let suffix = text[padding...]
            guard text.count % 4 == 0, (1...2).contains(suffix.count), suffix.allSatisfy({ $0 == "=" }),
                  count % 4 == 4 - suffix.count else { throw JsEngineError.exception("Invalid base64 padding") }
        } else {
            guard text.count % 4 != 1 else { throw JsEngineError.exception("Invalid base64 length") }
            text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        }
        if flags & 8 != 0 { text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") }
        guard let data = Data(base64Encoded: text) else { throw JsEngineError.exception("Invalid base64 input") }
        return data
    }

    static func decodeURI(_ value: String, charset name: String = "UTF-8") throws -> String {
        _ = try charset(name)
        let characters = Array(value)
        var result = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "+" { result += " "; index += 1 }
            else if characters[index] == "%" {
                var bytes = Data()
                while index < characters.count, characters[index] == "%" {
                    guard index + 2 < characters.count,
                          let byte = UInt8(String(characters[(index + 1)...(index + 2)]), radix: 16) else {
                        throw JsEngineError.exception("Invalid percent escape at position \(index)")
                    }
                    bytes.append(byte); index += 3
                }
                result += try decode(bytes, charset: name)
            } else { result.append(characters[index]); index += 1 }
        }
        return result
    }

    static func url(_ value: String, base: String?) throws -> [String: Any] {
        guard let url = URL(string: value, relativeTo: base.flatMap(URL.init(string:)))?.absoluteURL,
              let scheme = url.scheme, ["http", "https", "ftp", "file", "jar"].contains(scheme.lowercased()),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw JsEngineError.exception("Invalid URL: \(value)")
        }
        let host = parts.host ?? ""
        var parameters: [String: String]?
        if let query = parts.percentEncodedQuery {
            parameters = [:]
            for item in query.components(separatedBy: "&") {
                let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if pair.count == 2 { parameters?[String(pair[0])] = try decodeURI(String(pair[1])) }
            }
        }
        let port = parts.port.flatMap { $0 > 0 ? ":\($0)" : nil } ?? ""
        return ["host": host, "origin": scheme + "://" + host + port,
                "pathname": parts.percentEncodedPath, "searchParams": parameters as Any? ?? NSNull()]
    }
}
