import Foundation

public enum ChineseConverterError: Error, Equatable {
    case missingDictionary(String)
    case invalidDictionary(String, Int)
}

public enum ChineseConverter {
    private struct DictionaryTable {
        var replacements: [String: String] = [:]
        var longestByInitial: [Unicode.Scalar: Int] = [:]

        init(files: [String]) throws {
            for file in files {
                guard let url = Bundle.module.url(forResource: file, withExtension: "txt", subdirectory: "OpenCC") else {
                    throw ChineseConverterError.missingDictionary(file)
                }
                let text = try String(contentsOf: url, encoding: .utf8)
                for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    if line.isEmpty || line.hasPrefix("#") { continue }
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                    guard fields.count == 2, let initial = fields[0].unicodeScalars.first,
                          let replacement = fields[1].split(whereSeparator: { $0.isWhitespace }).first else {
                        throw ChineseConverterError.invalidDictionary(file, index + 1)
                    }
                    replacements[String(fields[0])] = String(replacement)
                    longestByInitial[initial] = max(longestByInitial[initial] ?? 0, fields[0].unicodeScalars.count)
                }
            }
        }

        func convert(_ text: String) throws -> String {
            let scalars = Array(text.unicodeScalars)
            var index = 0, result = ""
            result.reserveCapacity(text.utf8.count)
            while index < scalars.count {
                if index % 256 == 0 { try Task.checkCancellation() }
                var matched = false
                if let longest = longestByInitial[scalars[index]] {
                    for length in stride(from: min(longest, scalars.count - index), through: 1, by: -1) {
                        let key = String(String.UnicodeScalarView(scalars[index..<(index + length)]))
                        if let replacement = replacements[key] {
                            result += replacement
                            index += length
                            matched = true
                            break
                        }
                    }
                }
                if !matched { result.unicodeScalars.append(scalars[index]); index += 1 }
            }
            return result
        }
    }

    private static let simplified = Result { try DictionaryTable(files: ["TSCharacters", "TSPhrases"]) }
    private static let traditional = Result { try DictionaryTable(files: ["STCharacters", "STPhrases"]) }

    public static func t2s(_ text: String) throws -> String {
        try simplified.get().convert(text)
    }

    public static func s2t(_ text: String) throws -> String {
        try traditional.get().convert(text)
    }

    public static func convert(_ text: String, type: Int) throws -> String {
        switch type {
        case 1: return try t2s(text)
        case 2: return try s2t(text)
        default: return text
        }
    }
}
