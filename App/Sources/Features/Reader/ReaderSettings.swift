import Foundation
import CoreFoundation
import LegadoCore

enum ReaderTheme: String, CaseIterable, Codable {
    case day, night, eyeCare
}

struct ReaderSettings: Equatable {
    var configuration: ReadBookConfig
    var autoReadSpeed: Double = 10
    var hideStatusBar = false
    var theme: ReaderTheme = .day
    var isEInk = false
    /// Present only while the e-ink theme is active.
    var eInk: EInkSettings?
    var hidesStatusBar: Bool { hideStatusBar || isEInk && eInk?.hideStatusBar == true }
    var textFullJustify = true
    var textBottomJustify = true
    var useZhLayout = false
    var hangingPunctuation = false
    var noAnimScrollPage = false
    var punctuationCompress = "none"

    init(configuration: ReadBookConfig = ReadBookConfig()) { self.configuration = configuration }

    var darkStatusIcons: Bool {
        isEInk ? configuration.darkStatusIconEInk : theme == .night ? configuration.darkStatusIconNight : configuration.darkStatusIcon
    }

    var textSize: Double {
        get { Double(configuration.textSize) }
        set { configuration.textSize = Self.integer(newValue) }
    }
    var titleSize: Double {
        get { Double(configuration.titleSize) }
        set { configuration.titleSize = Self.integer(newValue) }
    }
    var titleTopSpacing: Double {
        get { Double(configuration.titleTopSpacing) }
        set { configuration.titleTopSpacing = Self.integer(newValue) }
    }
    var titleBottomSpacing: Double {
        get { Double(configuration.titleBottomSpacing) }
        set { configuration.titleBottomSpacing = Self.integer(newValue) }
    }
    var paragraphSpacing: Double {
        get { Double(configuration.paragraphSpacing) }
        set { configuration.paragraphSpacing = Self.integer(newValue) }
    }
    var paddingLeft: Double {
        get { Double(configuration.paddingLeft) }
        set { configuration.paddingLeft = Self.integer(newValue) }
    }
    var paddingRight: Double {
        get { Double(configuration.paddingRight) }
        set { configuration.paddingRight = Self.integer(newValue) }
    }
    var paddingTop: Double {
        get { Double(configuration.paddingTop) }
        set { configuration.paddingTop = Self.integer(newValue) }
    }
    var paddingBottom: Double {
        get { Double(configuration.paddingBottom) }
        set { configuration.paddingBottom = Self.integer(newValue) }
    }
    var lineSpacingExtra: Double {
        get { Double(configuration.lineSpacingExtra) }
        set { configuration.lineSpacingExtra = Self.integer(newValue) }
    }
    var titleMode: Int {
        get { configuration.titleMode }
        set { configuration.titleMode = newValue }
    }
    var textFont: String {
        get { configuration.textFont }
        set { configuration.textFont = newValue }
    }
    var pageAnim: Int {
        get { configuration.pageAnim }
        set { configuration.pageAnim = newValue }
    }
    var letterSpacing: Double {
        get { configuration.letterSpacing }
        set { configuration.letterSpacing = newValue }
    }
    var paragraphIndent: String {
        get { configuration.paragraphIndent }
        set { configuration.paragraphIndent = newValue }
    }
    var lineSpacingMultiplier: Double {
        get { lineSpacingExtra / 10 }
        set { lineSpacingExtra = newValue * 10 }
    }

    var backgroundValue: String {
        if isEInk, let paper = eInk?.paper.argb, configuration.bgTypeEInk == 0 { return ARGBColor(paper).hex }
        return isEInk ? configuration.bgStrEInk : theme == .night ? configuration.bgStrNight : configuration.bgStr
    }

    var backgroundType: Int {
        isEInk ? configuration.bgTypeEInk : theme == .night ? configuration.bgTypeNight : configuration.bgType
    }

    func backgroundImageURL(directory: URL) throws -> URL? {
        switch backgroundType {
        case 0: return nil
        case 1:
            guard let url = ReaderBackgroundResources.url(named: backgroundValue) else {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: backgroundValue])
            }
            return url
        case 2:
            let name = (backgroundValue as NSString).lastPathComponent
            guard !name.isEmpty, name != ".", name != ".." else { throw CocoaError(.fileReadInvalidFileName) }
            let url = directory.appendingPathComponent(name)
            guard url.resolvingSymlinksInPath().deletingLastPathComponent() == directory.resolvingSymlinksInPath() else {
                throw CocoaError(.fileReadNoPermission)
            }
            return url
        default: throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    private static func integer(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(Double(Int32.max), max(Double(Int32.min), value)))
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        var settings = Self()
        do {
            if let data = defaults.data(forKey: "Legado.readerConfiguration") {
                settings.configuration = try JSONDecoder().decode(ReadBookConfig.self, from: data)
            }
            var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings.configuration)) as! [String: Any]
            mergePreferences(into: &fields, defaults: defaults)
            settings.configuration = try JSONDecoder().decode(ReadBookConfig.self, from: JSONSerialization.data(withJSONObject: fields))
        } catch { NSLog("Unable to load reader configuration: %@", error.localizedDescription) }
        settings.autoReadSpeed = defaults.object(forKey: "autoReadSpeed") == nil ? 10 : defaults.double(forKey: "autoReadSpeed")
        settings.hideStatusBar = defaults.bool(forKey: "hideStatusBar")
        settings.theme = defaults.bool(forKey: "isNightTheme") ? .night :
            (defaults.bool(forKey: "Legado.readerEyeCare") || defaults.string(forKey: "bgStr") == "#CCE8CF" ? .eyeCare : .day)
        settings.textFullJustify = defaults.object(forKey: "textFullJustify") == nil ? true : defaults.bool(forKey: "textFullJustify")
        settings.textBottomJustify = defaults.object(forKey: "textBottomJustify") == nil ? true : defaults.bool(forKey: "textBottomJustify")
        settings.useZhLayout = defaults.bool(forKey: "useZhLayout")
        settings.noAnimScrollPage = defaults.bool(forKey: "noAnimScrollPage")
        settings.hangingPunctuation = defaults.bool(forKey: "hangingPunctuation")
        settings.punctuationCompress = defaults.string(forKey: "punctuationCompress") ?? "none"
        return settings.normalized
    }

    static func mergePreferences(into fields: inout [String: Any], defaults: UserDefaults) {
        for key in fields.keys {
            guard let raw = defaults.object(forKey: key), let expected = fields[key] else { continue }
            var value: Any?
            if let number = expected as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    switch String(describing: raw).lowercased() {
                    case "true", "yes", "1": value = true
                    case "false", "no", "0": value = false
                    default: break
                    }
                } else if let numeric = Double(String(describing: raw)), numeric.isFinite {
                    value = numeric
                }
            } else if expected is String { value = raw as? String }
            else if expected is [Any] { value = raw as? [Any] }
            guard let value else {
                NSLog("Ignoring invalid reader preference: %@", key)
                continue
            }
            var candidate = fields
            candidate[key] = value
            do {
                let data = try JSONSerialization.data(withJSONObject: candidate)
                _ = try JSONDecoder().decode(ReadBookConfig.self, from: data)
                fields = candidate
            } catch { NSLog("Ignoring invalid reader preference %@: %@", key, error.localizedDescription) }
        }
    }

    var normalized: Self {
        var value = self
        func clamp(_ input: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            input.isFinite ? min(range.upperBound, max(range.lowerBound, input)) : fallback
        }
        value.textSize = clamp(textSize, 5...50, 20)
        value.titleSize = clamp(titleSize, -8...48, 0)
        value.titleMode = (0...3).contains(titleMode) ? titleMode : 0
        value.titleTopSpacing = clamp(titleTopSpacing, 0...400, 0)
        value.titleBottomSpacing = clamp(titleBottomSpacing, 0...400, 0)
        value.autoReadSpeed = clamp(autoReadSpeed, 1...600, 10)
        value.pageAnim = (0...4).contains(pageAnim) ? pageAnim : 0
        value.configuration.pageAnimEInk = (0...4).contains(configuration.pageAnimEInk) ? configuration.pageAnimEInk : 4
        value.lineSpacingExtra = clamp(lineSpacingExtra, -10...40, 12)
        value.paragraphSpacing = clamp(paragraphSpacing, 0...20, 2)
        value.letterSpacing = clamp(letterSpacing, -0.5...0.5, 0.1)
        value.paddingLeft = clamp(paddingLeft, 0...100, 16)
        value.paddingRight = clamp(paddingRight, 0...100, 16)
        value.paddingTop = clamp(paddingTop, 0...400, 6)
        value.paddingBottom = clamp(paddingBottom, 0...400, 6)
        for path in [\ReadBookConfig.headerPaddingTop, \.headerPaddingBottom, \.footerPaddingTop, \.footerPaddingBottom] {
            value.configuration[keyPath: path] = min(400, max(0, configuration[keyPath: path]))
        }
        for path in [\ReadBookConfig.headerPaddingLeft, \.headerPaddingRight, \.footerPaddingLeft, \.footerPaddingRight] {
            value.configuration[keyPath: path] = min(100, max(0, configuration[keyPath: path]))
        }
        value.configuration.reviewIconScale = min(200, max(50, configuration.reviewIconScale))
        value.configuration.bgAlpha = min(100, max(0, configuration.bgAlpha))
        value.configuration.underlineMode = min(6, max(0, configuration.underlineMode))
        value.configuration.underlineWidth = clamp(configuration.underlineWidth, 0...10, 1)
        value.configuration.underlineDistance = clamp(configuration.underlineDistance, 0...30, 4)
        if !["none", "lineEnd", "adjacent", "adjacentLineEnd", "all"].contains(value.punctuationCompress) { value.punctuationCompress = "none" }
        value.configuration.textBold = min(2, max(0, configuration.textBold))
        value.configuration.titleBold = min(2, max(-1, configuration.titleBold))
        value.configuration.titleLineSpacingExtra = min(30, max(-20, configuration.titleLineSpacingExtra))
        return value
    }

    func save(to defaults: UserDefaults = .standard) {
        let value = normalized
        do {
            let data = try JSONEncoder().encode(value.configuration)
            defaults.set(data, forKey: "Legado.readerConfiguration")
            let fields = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            for (key, field) in fields { defaults.set(field, forKey: key) }
            for key in ["tipHeaderLeftTemplate", "tipHeaderMiddleTemplate", "tipHeaderRightTemplate", "tipFooterLeftTemplate", "tipFooterMiddleTemplate", "tipFooterRightTemplate"]
                where fields[key] == nil { defaults.removeObject(forKey: key) }
        } catch { NSLog("Unable to save reader configuration: %@", error.localizedDescription) }
        defaults.set(value.textFullJustify, forKey: "textFullJustify")
        defaults.set(value.textBottomJustify, forKey: "textBottomJustify")
        defaults.set(value.useZhLayout, forKey: "useZhLayout")
        defaults.set(value.noAnimScrollPage, forKey: "noAnimScrollPage")
        defaults.set(value.hangingPunctuation, forKey: "hangingPunctuation")
        defaults.set(value.punctuationCompress, forKey: "punctuationCompress")
        defaults.set(value.autoReadSpeed, forKey: "autoReadSpeed")
        defaults.set(value.hideStatusBar, forKey: "hideStatusBar")
        defaults.set(value.theme == .night, forKey: "isNightTheme")
        defaults.set(value.theme == .eyeCare, forKey: "Legado.readerEyeCare")
    }
}
