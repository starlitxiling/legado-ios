import Foundation

// Kotlin cb664b84d BookHelp.getDurChapter 的默认局部搜索路径。
enum BookChapterLocator {
    private static let digits = "0-9零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟"

    static func locate(oldIndex: Int, oldTitle: String?, oldCount: Int, titles: [String], oldURL: String?, urls: [String]) -> Int {
        if oldIndex <= 0 { return 0 }
        if titles.isEmpty { return oldIndex }
        let expected = oldCount == 0 ? oldIndex : Int(Int64(oldIndex) * Int64(titles.count) / Int64(oldCount))
        let lower = max(0, min(oldIndex, expected) - 10)
        let upper = min(titles.count - 1, max(oldIndex, expected) + 10)
        if lower <= upper {
            let oldName = Set(pureName(oldTitle).utf16)
            if !oldName.isEmpty {
                var best = 0
                var similarity = 0.0
                for index in lower...upper {
                    let name = Set(pureName(titles[index]).utf16)
                    let score = Double(oldName.intersection(name).count) / Double(oldName.union(name).count)
                    if score > similarity || score == similarity && abs(index - expected) < abs(best - expected) {
                        best = index
                        similarity = score
                    }
                }
                if similarity > 0.96 { return best }
            }
            let number = chapterNumber(oldTitle)
            if number > 0 {
                for index in lower...upper where chapterNumber(titles[index]) == number { return index }
            }
        }
        if let oldURL, !oldURL.isEmpty {
            let candidates = urls.indices.filter { urls[$0] == oldURL && titles.indices.contains($0) }
            if let index = candidates.min(by: { abs($0 - expected) < abs($1 - expected) }) { return index }
        }
        return min(max(0, titles.count - 1), oldIndex)
    }

    private static func normalized(_ text: String?) -> String {
        let half = String(String.UnicodeScalarView((text ?? "").unicodeScalars.map { scalar in
            let value = scalar.value
            return UnicodeScalar(value == 12288 ? 32 : (65281...65374).contains(value) ? value - 65248 : value)!
        }))
        return half.replacingOccurrences(of: #"[ \t\n\x0B\f\r]"#, with: "", options: .regularExpression)
    }

    private static func pureName(_ title: String?) -> String {
        let prefix = "^.*?第(?:[\(digits)]+)[章节篇回集话](?!$)|^(?:[\(digits)]+[,:、])*(?:[\(digits)]+)(?:[,:、](?!$)|\\.(?=[^0-9]))"
        let brackets = #"(?!^)(?:[〖【《〔\[{(][^〖【《〔\[{()〕》】〗\]}]+)?[)〕》】〗\]}]$|^[〖【《〔\[{(](?:[^〖【《〔\[{()〕》】〗\]}]+[〕》】〗\]})])?(?!$)"#
        let other = #"[^a-zA-Z_0-9\u4E00-\u9FEF〇\u3400-\u4DBF\x{20000}-\x{2A6DF}\x{2A700}-\x{2EBEF}]"#
        return [prefix, brackets, other].reduce(normalized(title)) {
            $0.replacingOccurrences(of: $1, with: "", options: .regularExpression)
        }
    }

    private static func chapterNumber(_ title: String?) -> Int {
        let text = normalized(title)
        for pattern in [".*?第([\(digits)]+)[章节篇回集话]",
                        "^(?:[\(digits)]+[,:、])*([\(digits)]+)(?:[,:、]|\\.[^0-9])"] {
            let regex = try! NSRegularExpression(pattern: pattern)
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let number = String(text[range])
                if let value = Int32(number) { return Int(value) }
                return chineseNumber(number)
            }
        }
        return -1
    }

    private static func chineseNumber(_ text: String) -> Int {
        let values: [Character: Int32] = ["零": 0, "〇": 0, "一": 1, "壹": 1, "二": 2, "两": 2, "贰": 2,
            "三": 3, "叁": 3, "四": 4, "肆": 4, "五": 5, "伍": 5, "六": 6, "陆": 6, "七": 7, "柒": 7,
            "八": 8, "捌": 8, "九": 9, "玖": 9, "十": 10, "拾": 10, "百": 100, "佰": 100,
            "千": 1000, "仟": 1000, "万": 10000]
        let characters = Array(text)
        var result: Int32 = 0
        var temporary: Int32 = 0
        for (index, character) in characters.enumerated() {
            guard let value = values[character] else { return -1 }
            if value == 10000 {
                result = (result &+ temporary) &* value
                temporary = 0
            } else if value >= 10 {
                if temporary == 0 { temporary = 1 }
                result = result &+ (value &* temporary)
                temporary = 0
            } else if index >= 2, index == characters.count - 1, let previous = values[characters[index - 1]], previous > 10 {
                temporary = value &* previous / 10
            } else {
                temporary = temporary &* 10 &+ value
            }
        }
        return Int(result &+ temporary)
    }
}
