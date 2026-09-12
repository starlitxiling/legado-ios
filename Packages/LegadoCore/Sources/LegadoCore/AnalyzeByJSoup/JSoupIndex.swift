import Foundation

/// 规格 §5.5，L181-187：从尾部扫描，识别失败时保留完整 CSS 选择器。
struct JSoupIndex {
    private enum Entry { case index(Int), range(Int?, Int?, Int) }
    private var entries: [Entry] = []
    private var mode: Character = " "
    private(set) var selector: String

    init(_ rule: String) throws {
        let text = Array(asciiTrim(rule))
        selector = String(text)
        guard let last = text.last else { throw RuleAnalyzer.AnalysisError.exhausted }
        var cursor = text.count - 1
        var digits = ""
        var negative = false
        var range: [Int?] = []
        func number() throws -> Int? {
            guard !digits.isEmpty else { return nil }
            guard let value = Int32(digits) else { throw AnalyzeByJSoup.EvaluationError.invalidIndex }
            return negative ? -Int(value) : Int(value)
        }
        if last == "]" {
            cursor -= 1
            while cursor >= 0 {
                var character = text[cursor]
                if character == " " { cursor -= 1; continue }
                if character >= "0" && character <= "9" { digits.insert(character, at: digits.startIndex) }
                else if character == "-" { negative = true }
                else {
                    let value = try number()
                    if character == ":" { range.append(value) }
                    else {
                        if range.isEmpty {
                            guard let value else { break }
                            entries.append(.index(value))
                        } else {
                            let step: Int
                            if range.count == 2 {
                                guard let value = range[0] else { throw AnalyzeByJSoup.EvaluationError.invalidIndex }
                                step = value
                            } else { step = 1 }
                            entries.append(.range(value, range.last!, step))
                            range.removeAll()
                        }
                        if character == "!" {
                            mode = "!"
                            repeat { cursor -= 1 } while cursor > 0 && text[cursor] == " "
                            guard cursor >= 0 else { throw AnalyzeByJSoup.EvaluationError.invalidIndex }
                            character = text[cursor]
                        }
                        if character == "[" {
                            selector = String(text[..<cursor])
                            if mode != "!" { mode = "." }
                            return
                        }
                        if character != "," { break }
                    }
                    digits = ""
                    negative = false
                }
                cursor -= 1
            }
        } else {
            while cursor >= 0 {
                let character = text[cursor]
                if character == " " { cursor -= 1; continue }
                if character >= "0" && character <= "9" { digits.insert(character, at: digits.startIndex) }
                else if character == "-" { negative = true }
                else {
                    guard ["!", ".", ":"].contains(character) else { break }
                    guard let value = try number() else { throw AnalyzeByJSoup.EvaluationError.invalidIndex }
                    entries.append(.index(value))
                    if character != ":" {
                        mode = character
                        selector = String(text[..<cursor])
                        return
                    }
                    digits = ""
                    negative = false
                }
                cursor -= 1
            }
        }
        mode = " "
    }

    func apply<T>(_ values: [T]) -> [T] {
        guard mode != " ", !values.isEmpty else { return values }
        let count = values.count
        var indices: [Int] = []
        var seen: Set<Int> = []
        func append(_ index: Int) {
            if index >= 0, index < count, seen.insert(index).inserted { indices.append(index) }
        }
        for entry in entries.reversed() {
            switch entry {
            case .index(let index): append(index < 0 ? index + count : index)
            case .range(let left, let right, let step):
                var start = left ?? 0
                var end = right ?? (count - 1)
                if start < 0 { start += count }
                if end < 0 { end += count }
                if (start < 0 && end < 0) || (start >= count && end >= count) { continue }
                start = min(max(start, 0), count - 1)
                end = min(max(end, 0), count - 1)
                if start == end || step >= count { append(start); continue }
                let distance = step > 0 ? step : (-step < count ? step + count : 1)
                for index in stride(from: start, through: end, by: end > start ? distance : -distance) { append(index) }
            }
        }
        return mode == "!" ? values.enumerated().filter { !seen.contains($0.offset) }.map(\.element) : indices.map { values[$0] }
    }
}
