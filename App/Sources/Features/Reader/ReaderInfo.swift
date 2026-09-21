import Foundation

struct ReaderInfoValues {
    var bookName = ""
    var chapterTitle = ""
    var time = ""
    var battery = 0
    var page = ""
    var totalPages = ""
    var readProgress = ""
    var chapter = ""
    var totalChapters = ""
}

enum ReaderInfoPart: Equatable {
    case text(String)
    case battery(Int, Bool)
}

enum ReaderInfo {
    static let choices: [(Int, String)] = [(0, "无"), (7, "书名"), (1, "标题"), (2, "时间"),
        (3, "电量"), (10, "电量%"), (4, "页数"), (5, "进度(%)"), (11, "进度(xx/yyy)"),
        (6, "页数及进度"), (8, "时间及电量"), (9, "时间及电量%")]
    static let templates = [0: "", 7: "{书名}", 1: "{章节}", 2: "{时间}", 3: "{电量图标}", 10: "{电量}",
        4: "{页码}/{总页数}", 5: "{阅读进度}", 11: "{章节序号}/{章节总数}",
        6: "{页码}/{总页数}  {阅读进度}", 8: "{时间}  {电量图标}", 9: "{时间} {电量}"]

    static func parts(code: Int, template: String? = nil, values: ReaderInfoValues) -> [ReaderInfoPart] {
        let chars = Array(template ?? templates[code] ?? "")
        let battery = min(100, max(0, values.battery))
        let replacements = ["{书名}": values.bookName, "{章节}": values.chapterTitle, "{时间}": values.time,
            "{电量}": "\(battery)%", "{页码}": values.page, "{总页数}": values.totalPages,
            "{阅读进度}": values.readProgress, "{章节序号}": values.chapter, "{章节总数}": values.totalChapters]
        var output: [ReaderInfoPart] = [], text = "", index = 0
        while index < chars.count {
            guard chars[index] == "{" else { text.append(chars[index]); index += 1; continue }
            var depth = 0, end: Int?, nested = false
            for cursor in index..<chars.count {
                if chars[cursor] == "{" { depth += 1; nested = nested || depth > 1 }
                if chars[cursor] == "}" { depth -= 1; if depth == 0 { end = cursor; break } }
            }
            guard let end else { text.append(chars[index]); index += 1; continue }
            let token = String(chars[index...end])
            let outer = (index > 0 && chars[index - 1] == "{") || (end + 1 < chars.count && chars[end + 1] == "}")
            if nested || outer { text += token }
            else if token == "{电量图标}" || token == "{电量图标数值}" {
                if !text.isEmpty { output.append(.text(text)); text = "" }
                output.append(.battery(battery, token == "{电量图标数值}"))
            } else { text += replacements[token] ?? token }
            index = end + 1
        }
        if !text.isEmpty { output.append(.text(text)) }
        return output
    }
}
