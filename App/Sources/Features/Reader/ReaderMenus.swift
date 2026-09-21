import Foundation

struct ReaderMenuPartition: Equatable {
    var primary: [String]
    var more: [String]
    static let readerActions: [(String, String)] = [("bookmark", "添加书签"), ("highlightRule", "高亮规则"),
        ("editContent", "编辑内容"), ("pageAnim", "翻页动画（本书）"), ("getProgress", "拉取云端进度"),
        ("coverProgress", "覆盖云端进度"), ("reverseContent", "反转内容"), ("simulatedReading", "模拟追读"),
        ("replace", "替换管理"), ("sameTitleRemoved", "移除重复标题"), ("reSegment", "重新分段"),
        ("delRubyTag", "删除 ruby 标签"), ("delHTag", "删除 h 标签"), ("imageStyle", "图片样式"),
        ("reimportSource", "重新导入本书书源"), ("updateToc", "TXT 目录规则"), ("effectiveReplaces", "手动替换"),
        ("log", "日志"), ("help", "帮助")]
    static let textActions: [(String, String)] = [("replace", "替换"), ("copy", "复制"), ("bookmark", "书签"),
        ("highlight", "高亮"), ("aloud", "朗读"), ("dict", "词典"), ("search", "搜索"), ("browser", "浏览器"),
        ("share", "分享"), ("processText", "系统文本操作")]

    static func load(selection: Bool, defaults: UserDefaults = .standard) -> Self {
        let actions = selection ? textActions : readerActions
        let fallback = Self(primary: Array(actions.prefix(selection ? 5 : actions.count).map(\.0)),
                            more: selection ? Array(actions.dropFirst(5).map(\.0)) : [])
        guard let json = defaults.string(forKey: selection ? "textSelectMenuConfig" : "readerMenuConfig"),
              let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fallback }
        return Self(primary: values[selection ? "bar" : "primary"] as? [String] ?? [],
                    more: values["more"] as? [String] ?? []).normalized(selection: selection)
    }
    func normalized(selection: Bool) -> Self {
        let known = (selection ? Self.textActions : Self.readerActions).map(\.0)
        var seen = Set<String>()
        var first = primary.filter { known.contains($0) && seen.insert($0).inserted }
        var second = more.filter { known.contains($0) && seen.insert($0).inserted }
        let missing = known.filter { seen.insert($0).inserted }
        if selection { second += missing } else { first += missing }
        return Self(primary: first, more: second)
    }
    func save(selection: Bool, defaults: UserDefaults = .standard) throws {
        let value = normalized(selection: selection)
        let data = try JSONSerialization.data(withJSONObject: [selection ? "bar" : "primary": value.primary, "more": value.more])
        defaults.set(String(decoding: data, as: UTF8.self), forKey: selection ? "textSelectMenuConfig" : "readerMenuConfig")
    }
}

enum ReaderKeyboard {
    static func androidCode(character: String) -> Int? {
        if character.utf8.count == 1, let byte = character.lowercased().utf8.first, byte >= 97, byte <= 122 { return Int(byte - 97) + 29 }
        if character.utf8.count == 1, let byte = character.utf8.first, byte >= 48, byte <= 57 { return Int(byte - 48) + 7 }
        switch character {
        case " ": return 62
        case "\r", "\n": return 66
        case "\u{f700}": return 19
        case "\u{f701}": return 20
        case "\u{f702}": return 21
        case "\u{f703}": return 22
        case "\u{f72c}": return 92
        case "\u{f72d}": return 93
        case "\u{1b}": return 111
        default: return nil
        }
    }
    static func forward(code: Int, previous: String, next: String) -> Bool? {
        func codes(_ text: String, fallback: Set<Int>) -> Set<Int> {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return fallback }
            return Set(text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        if codes(previous, fallback: [19, 21, 92]).contains(code) { return false }
        if codes(next, fallback: [20, 22, 62, 93]).contains(code) { return true }
        return nil
    }
}
