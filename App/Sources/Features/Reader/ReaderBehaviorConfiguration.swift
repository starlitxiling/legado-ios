import Foundation
import LegadoCore

struct ReaderPreferenceDefinition {
    enum Kind {
        case toggle(Bool)
        case choice(String, [(String, String)])
        case number(Int, ClosedRange<Int>, Int)
        case action
    }
    let key: String
    let title: String
    let kind: Kind
    var initial: AndroidPreferenceValue? {
        switch kind {
        case .toggle(let value): return .boolean(value)
        case .choice(let value, _): return .string(value)
        case .number(let value, _, _): return .int(Int32(value))
        case .action: return nil
        }
    }
    init(_ key: String, _ title: String, _ kind: Kind) { self.key = key; self.title = title; self.kind = kind }
}

struct ReaderBehaviorConfiguration: Equatable {
    private(set) var values: [String: AndroidPreferenceValue]
    static let definitions: [ReaderPreferenceDefinition] = [
        .init("screenOrientation", "屏幕方向", .choice("0", [("0", "跟随系统"), ("1", "竖屏"), ("2", "横屏"), ("3", "感应方向"), ("4", "反向竖屏"), ("5", "反向横屏")])),
        .init("keep_light", "屏幕常亮", .choice("0", [("0", "跟随系统"), ("60", "1 分钟"), ("300", "5 分钟"), ("600", "10 分钟"), ("-1", "始终")])),
        .init("hideStatusBar", "隐藏状态栏", .toggle(false)),
        .init("hideNavigationBar", "隐藏 Home 指示条", .toggle(false)),
        .init("readBodyToLh", "正文扩展到刘海区域", .toggle(true)),
        .init("paddingDisplayCutouts", "避让显示开孔", .toggle(false)),
        .init("doubleHorizontalPage", "双页显示", .choice("0", [("0", "单页"), ("1", "双页"), ("2", "横屏双页"), ("3", "平板或横屏双页")])),
        .init("progressBarBehavior", "进度条行为", .choice("page", [("page", "本章页码"), ("chapter", "全书章节")])),
        .init("useZhLayout", "中文分行", .toggle(false)),
        .init("textFullJustify", "两端对齐", .toggle(true)),
        .init("hangingPunctuation", "悬挂标点", .toggle(false)),
        .init("punctuationCompress", "标点挤压", .choice("none", [("none", "关闭"), ("lineEnd", "行末"), ("adjacent", "相邻"), ("adjacentLineEnd", "相邻及行末"), ("all", "全部")])),
        .init("textBottomJustify", "底部对齐", .toggle(true)),
        .init("adaptSpecialStyle", "适配特殊样式", .toggle(true)),
        .init("mouseWheelPage", "鼠标滚轮翻页", .toggle(true)),
        .init("mouseWheelScrollSpeed", "鼠标滚轮速度", .number(100, 10...400, 10)),
        .init("volumeKeyPage", "音量键翻页", .toggle(true)),
        .init("volumeKeyPageOnPlay", "播放时音量键翻页", .toggle(false)),
        .init("keyPageOnLongPress", "按键长按连续翻页", .toggle(false)),
        .init("pullToToggleBookmark", "下拉添加或移除书签", .toggle(false)),
        .init("pullBookmarkDistance", "下拉书签距离 (0 为默认)", .number(0, 0...400, 1)),
        .init("pageTouchSlop", "翻页触发距离 (0 为默认)", .number(0, 0...200, 1)),
        .init("pageTouchClick", "点击移动容差 (0 为默认)", .number(0, 0...100, 1)),
        .init("autoChangeSource", "正文失败自动换源", .toggle(true)),
        .init("selectText", "长按选择文本", .toggle(true)),
        .init("longPressSelectParagraph", "长按选择整段", .toggle(false)),
        .init("twoFingerReplacePreview", "双指替换预览", .toggle(false)),
        .init("showBrightnessView", "显示亮度条", .toggle(true)),
        .init("noAnimScrollPage", "无动画时允许滚动翻页", .toggle(false)),
        .init("clickImgWay", "点击图片方式", .choice("0", [("0", "默认行为"), ("1", "预览图片"), ("2", "兼容旧版"), ("3", "关闭点击"), ("4", "双击生效")])),
        .init("highlightActionTrigger", "高亮动作触发方式", .choice("click", [("click", "单击"), ("doubleTap", "双击"), ("longPress", "长按"), ("off", "关闭")])),
        .init("optimizeRender", "优化渲染", .toggle(false)),
        .init("clickRegionalConfig", "点击区域设置", .action),
        .init("disableReturnKey", "禁用返回手势与按键", .toggle(false)),
        .init("customPageKey", "自定义翻页按键", .action),
        .init("customTextMenu", "自定义选择菜单", .action),
        .init("customReaderMenu", "自定义阅读菜单", .action),
        .init("showReadTitleAddition", "显示章节附加信息", .toggle(true)),
        .init("showReadTitleChapterNameOnly", "只显示章节名", .toggle(false)),
        .init("readBarStyleFollowPage", "菜单跟随页面配色", .toggle(false)),
        .init("showBookMemo", "显示书籍备注", .toggle(false))
    ]
    static var defaults: [String: AndroidPreferenceValue] {
        Dictionary(uniqueKeysWithValues: definitions.compactMap { item in item.initial.map { (item.key, $0) } })
    }

    init(values: [String: AndroidPreferenceValue]) {
        self.values = Self.defaults
        for (key, value) in values { set(key, value) }
    }
    init(defaults: UserDefaults = .standard) {
        self.init(values: [:])
        for item in Self.definitions {
            guard let raw = defaults.object(forKey: item.key) else { continue }
            switch item.kind {
            case .toggle:
                switch String(describing: raw).lowercased() {
                case "true", "yes", "1": set(item.key, .boolean(true))
                case "false", "no", "0": set(item.key, .boolean(false))
                default: break
                }
            case .choice: if let value = raw as? String { set(item.key, .string(value)) }
            case .number:
                if let value = Int64(String(describing: raw)) { set(item.key, .int(Int32(clamping: value))) }
            case .action: break
            }
        }
    }
    mutating func set(_ key: String, _ value: AndroidPreferenceValue) {
        guard let item = Self.definitions.first(where: { $0.key == key }) else { return }
        switch (item.kind, value) {
        case (.toggle, .boolean): values[key] = value
        case (.choice(let fallback, let choices), .string(let text)):
            values[key] = .string(choices.contains(where: { $0.0 == text }) ? text : fallback)
        case (.number(_, let range, _), .int(let number)):
            values[key] = .int(Int32(min(range.upperBound, max(range.lowerBound, Int(number)))))
        default: break
        }
    }
    func boolean(_ key: String) -> Bool { if case .boolean(let value) = values[key] { return value }; return false }
    func string(_ key: String) -> String { if case .string(let value) = values[key] { return value }; return "" }
    func integer(_ key: String) -> Int { if case .int(let value) = values[key] { return Int(value) }; return 0 }
    func save(to defaults: UserDefaults = .standard) {
        for (key, value) in values {
            switch value {
            case .boolean(let flag): defaults.set(flag, forKey: key)
            case .string(let text): defaults.set(text, forKey: key)
            case .int(let number): defaults.set(Int(number), forKey: key)
            default: break
            }
        }
    }
    func doublePage(width: Double, height: Double, tablet: Bool) -> Bool {
        switch string("doubleHorizontalPage") {
        case "1": return true
        case "2": return width > height
        case "3": return tablet || width > height
        default: return false
        }
    }
    enum GestureResult: Equatable { case next, previous, bookmark, tap, none }
    /// Android stores these distances in pixels; `scale` converts them to points.
    func gesture(x: Double, y: Double, duration: Double, scale: Double = 1) -> GestureResult {
        guard x.isFinite, y.isFinite, duration.isFinite else { return .none }
        let pixels = scale.isFinite && scale > 0 ? scale : 1
        let swipe = integer("pageTouchSlop") == 0 ? 30 : Double(integer("pageTouchSlop")) / pixels
        let click = integer("pageTouchClick") == 0 ? 10 : Double(integer("pageTouchClick")) / pixels
        let bookmark = integer("pullBookmarkDistance") == 0 ? 80 : Double(integer("pullBookmarkDistance")) / pixels
        if boolean("pullToToggleBookmark"), y >= bookmark, abs(y) > abs(x) { return .bookmark }
        if abs(x) >= swipe, abs(x) > abs(y) { return x < 0 ? .next : .previous }
        if abs(x) <= click, abs(y) <= click, duration < 0.4 { return .tap }
        return .none
    }
}
