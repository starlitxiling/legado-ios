import Foundation

enum ReaderTheme: String, CaseIterable, Codable {
    case day, night, eyeCare
}

struct ReaderSettings: Equatable {
    var textSize: Double = 20
    var titleSize: Double = 0
    var titleMode: Int = 0
    var titleTopSpacing: Double = 0
    var titleBottomSpacing: Double = 0
    var textFont = ""
    var pageAnim = 0
    var autoReadSpeed: Double = 10
    var hideStatusBar = false
    var lineSpacingMultiplier: Double = 1.2
    var paragraphSpacing: Double = 2
    var paragraphIndent = "　　"
    var paddingLeft: Double = 16
    var paddingRight: Double = 16
    var paddingTop: Double = 6
    var paddingBottom: Double = 6
    var theme: ReaderTheme = .day

    static func load(from defaults: UserDefaults = .standard) -> Self {
        var value = Self()
        func number(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }
        value.textSize = number("textSize", 20)
        value.titleSize = number("titleSize", 0)
        value.titleMode = defaults.integer(forKey: "titleMode")
        value.titleTopSpacing = number("titleTopSpacing", 0)
        value.titleBottomSpacing = number("titleBottomSpacing", 0)
        value.textFont = defaults.string(forKey: "textFont") ?? ""
        value.pageAnim = defaults.integer(forKey: "pageAnim")
        value.autoReadSpeed = number("autoReadSpeed", 10)
        value.hideStatusBar = defaults.bool(forKey: "hideStatusBar")
        value.lineSpacingMultiplier = number("lineSpacingExtra", 12) / 10
        value.paragraphSpacing = number("paragraphSpacing", 2)
        value.paragraphIndent = defaults.string(forKey: "paragraphIndent") ?? "　　"
        value.paddingLeft = number("paddingLeft", 16)
        value.paddingRight = number("paddingRight", 16)
        value.paddingTop = number("paddingTop", 6)
        value.paddingBottom = number("paddingBottom", 6)
        value.theme = defaults.bool(forKey: "isNightTheme") ? .night :
            (defaults.string(forKey: "bgStr") == "#CCE8CF" ? .eyeCare : .day)
        return value.normalized
    }

    var normalized: Self {
        var value = self
        func clamp(_ input: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            input.isFinite ? min(range.upperBound, max(range.lowerBound, input)) : fallback
        }
        value.textSize = clamp(textSize, 12...48, 20)
        value.titleSize = clamp(titleSize, -8...48, 0)
        value.titleMode = (0...3).contains(titleMode) ? titleMode : 0
        value.titleTopSpacing = clamp(titleTopSpacing, 0...100, 0)
        value.titleBottomSpacing = clamp(titleBottomSpacing, 0...100, 0)
        value.autoReadSpeed = clamp(autoReadSpeed, 1...600, 10)
        value.pageAnim = (0...4).contains(pageAnim) ? pageAnim : 0
        value.lineSpacingMultiplier = clamp(lineSpacingMultiplier, 1...3, 1.2)
        value.paragraphSpacing = clamp(paragraphSpacing, 0...40, 2)
        value.paddingLeft = clamp(paddingLeft, 0...100, 16)
        value.paddingRight = clamp(paddingRight, 0...100, 16)
        value.paddingTop = clamp(paddingTop, 0...100, 6)
        value.paddingBottom = clamp(paddingBottom, 0...100, 6)
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        let value = normalized
        defaults.set(value.textSize, forKey: "textSize")
        defaults.set(value.titleSize, forKey: "titleSize")
        defaults.set(value.titleMode, forKey: "titleMode")
        defaults.set(value.titleTopSpacing, forKey: "titleTopSpacing")
        defaults.set(value.titleBottomSpacing, forKey: "titleBottomSpacing")
        defaults.set(value.textFont, forKey: "textFont")
        defaults.set(value.pageAnim, forKey: "pageAnim")
        defaults.set(value.autoReadSpeed, forKey: "autoReadSpeed")
        defaults.set(value.hideStatusBar, forKey: "hideStatusBar")
        defaults.set(value.lineSpacingMultiplier * 10, forKey: "lineSpacingExtra")
        defaults.set(value.paragraphSpacing, forKey: "paragraphSpacing")
        defaults.set(value.paragraphIndent, forKey: "paragraphIndent")
        defaults.set(value.paddingLeft, forKey: "paddingLeft")
        defaults.set(value.paddingRight, forKey: "paddingRight")
        defaults.set(value.paddingTop, forKey: "paddingTop")
        defaults.set(value.paddingBottom, forKey: "paddingBottom")
        defaults.set(value.theme == .night, forKey: "isNightTheme")
        defaults.set(value.theme == .eyeCare ? "#CCE8CF" : "#EEEEEE", forKey: "bgStr")
    }
}
