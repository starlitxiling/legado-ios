import Foundation

/// Kotlin cb664b84d 的 ReadBookConfig.Config；共享偏好独立保存。
public struct ReadBookConfig: Codable, Equatable, Sendable {
    public var name: String = ""
    public var bgStr: String = "#EEEEEE"
    public var bgStrNight: String = "#000000"
    public var bgStrEInk: String = "#FFFFFF"
    public var bgAlpha: Int = 100
    public var bgType: Int = 0
    public var bgTypeNight: Int = 0
    public var bgTypeEInk: Int = 0
    public var darkStatusIcon: Bool = true
    public var darkStatusIconNight: Bool = false
    public var darkStatusIconEInk: Bool = true
    public var textColor: String = "#3E3D3B"
    public var textColorNight: String = "#ADADAD"
    public var textColorEInk: String = "#000000"
    public var textAccentColor: String = "#E53935"
    public var textAccentColorNight: String = "#FE4D55"
    public var textAccentColorEInk: String = "#000000"
    public var pageAnim: Int = 0
    public var pageAnimEInk: Int = 4
    public var textFont: String = ""
    public var titleFont: String = ""
    public var titleBold: Int = -1
    public var textBold: Int = 0
    public var textSize: Int = 20
    public var letterSpacing: Double = 0.1
    public var lineSpacingExtra: Int = 12
    public var titleLineSpacingExtra: Int = 0
    public var paragraphSpacing: Int = 2
    public var titleMode: Int = 0
    public var titleSize: Int = 0
    public var titleColor: Int = 0
    public var splitChapterTitle: Bool = false
    public var titleNumberSize: Int = 0
    public var titleNumberColor: Int = 0
    public var titleNumberSpacing: Int = 0
    public var titleTopSpacing: Int = 0
    public var titleBottomSpacing: Int = 0
    public var paragraphIndent: String = "　　"
    public var underlineMode: Int = 0
    public var underlineColor: Int = 0
    public var underlineColorSet: Bool = false
    public var underlineWidth: Double = 1
    public var underlineDistance: Double = 4
    public var underlineBodyEnabled: Bool = true
    public var underlineTitleEnabled: Bool = true
    public var underlineConfigVersion: Int = 0
    public var reviewIconColor: Int = 0
    public var reviewIconSvg: String = ""
    public var reviewIconSvgTemplates: [ReviewIconSvgTemplate] = []
    public var reviewIconScale: Int = 100
    public var paddingBottom: Int = 6
    public var paddingLeft: Int = 16
    public var paddingRight: Int = 16
    public var paddingTop: Int = 6
    public var headerPaddingBottom: Int = 0
    public var headerPaddingLeft: Int = 16
    public var headerPaddingRight: Int = 16
    public var headerPaddingTop: Int = 0
    public var footerPaddingBottom: Int = 6
    public var footerPaddingLeft: Int = 16
    public var footerPaddingRight: Int = 16
    public var footerPaddingTop: Int = 6
    public var showHeaderLine: Bool = false
    public var showFooterLine: Bool = true
    public var tipHeaderLeft: Int = 2
    public var tipHeaderMiddle: Int = 0
    public var tipHeaderRight: Int = 3
    public var tipFooterLeft: Int = 1
    public var tipFooterMiddle: Int = 0
    public var tipFooterRight: Int = 6
    public var tipHeaderLeftTemplate: String? = nil
    public var tipHeaderMiddleTemplate: String? = nil
    public var tipHeaderRightTemplate: String? = nil
    public var tipFooterLeftTemplate: String? = nil
    public var tipFooterMiddleTemplate: String? = nil
    public var tipFooterRightTemplate: String? = nil
    public var tipTextSize: Int = 12
    public var tipColor: Int = 0
    public var tipDividerColor: Int = -1
    public var headerMode: Int = 0
    public var footerMode: Int = 0

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case name
        case bgStr
        case bgStrNight
        case bgStrEInk
        case bgAlpha
        case bgType
        case bgTypeNight
        case bgTypeEInk
        case darkStatusIcon
        case darkStatusIconNight
        case darkStatusIconEInk
        case textColor
        case textColorNight
        case textColorEInk
        case textAccentColor
        case textAccentColorNight
        case textAccentColorEInk
        case pageAnim
        case pageAnimEInk
        case textFont
        case titleFont
        case titleBold
        case textBold
        case textSize
        case letterSpacing
        case lineSpacingExtra
        case titleLineSpacingExtra
        case paragraphSpacing
        case titleMode
        case titleSize
        case titleColor
        case splitChapterTitle
        case titleNumberSize
        case titleNumberColor
        case titleNumberSpacing
        case titleTopSpacing
        case titleBottomSpacing
        case paragraphIndent
        case underlineMode
        case underlineColor
        case underlineColorSet
        case underlineWidth
        case underlineDistance
        case underlineBodyEnabled
        case underlineTitleEnabled
        case underlineConfigVersion
        case reviewIconColor
        case reviewIconSvg
        case reviewIconSvgTemplates
        case reviewIconScale
        case paddingBottom
        case paddingLeft
        case paddingRight
        case paddingTop
        case headerPaddingBottom
        case headerPaddingLeft
        case headerPaddingRight
        case headerPaddingTop
        case footerPaddingBottom
        case footerPaddingLeft
        case footerPaddingRight
        case footerPaddingTop
        case showHeaderLine
        case showFooterLine
        case tipHeaderLeft
        case tipHeaderMiddle
        case tipHeaderRight
        case tipFooterLeft
        case tipFooterMiddle
        case tipFooterRight
        case tipHeaderLeftTemplate
        case tipHeaderMiddleTemplate
        case tipHeaderRightTemplate
        case tipFooterLeftTemplate
        case tipFooterMiddleTemplate
        case tipFooterRightTemplate
        case tipTextSize
        case tipColor
        case tipDividerColor
        case headerMode
        case footerMode
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? name
        bgStr = try values.decodeIfPresent(String.self, forKey: .bgStr) ?? bgStr
        bgStrNight = try values.decodeIfPresent(String.self, forKey: .bgStrNight) ?? bgStrNight
        bgStrEInk = try values.decodeIfPresent(String.self, forKey: .bgStrEInk) ?? bgStrEInk
        bgAlpha = try values.decodeIfPresent(Int.self, forKey: .bgAlpha) ?? bgAlpha
        bgType = try values.decodeIfPresent(Int.self, forKey: .bgType) ?? bgType
        bgTypeNight = try values.decodeIfPresent(Int.self, forKey: .bgTypeNight) ?? bgTypeNight
        bgTypeEInk = try values.decodeIfPresent(Int.self, forKey: .bgTypeEInk) ?? bgTypeEInk
        darkStatusIcon = try values.decodeIfPresent(Bool.self, forKey: .darkStatusIcon) ?? darkStatusIcon
        darkStatusIconNight = try values.decodeIfPresent(Bool.self, forKey: .darkStatusIconNight) ?? darkStatusIconNight
        darkStatusIconEInk = try values.decodeIfPresent(Bool.self, forKey: .darkStatusIconEInk) ?? darkStatusIconEInk
        textColor = try values.decodeIfPresent(String.self, forKey: .textColor) ?? textColor
        textColorNight = try values.decodeIfPresent(String.self, forKey: .textColorNight) ?? textColorNight
        textColorEInk = try values.decodeIfPresent(String.self, forKey: .textColorEInk) ?? textColorEInk
        textAccentColor = try values.decodeIfPresent(String.self, forKey: .textAccentColor) ?? textAccentColor
        textAccentColorNight = try values.decodeIfPresent(String.self, forKey: .textAccentColorNight) ?? textAccentColorNight
        textAccentColorEInk = try values.decodeIfPresent(String.self, forKey: .textAccentColorEInk) ?? textAccentColorEInk
        pageAnim = try values.decodeIfPresent(Int.self, forKey: .pageAnim) ?? pageAnim
        pageAnimEInk = try values.decodeIfPresent(Int.self, forKey: .pageAnimEInk) ?? pageAnimEInk
        textFont = try values.decodeIfPresent(String.self, forKey: .textFont) ?? textFont
        titleFont = try values.decodeIfPresent(String.self, forKey: .titleFont) ?? titleFont
        titleBold = try values.decodeIfPresent(Int.self, forKey: .titleBold) ?? titleBold
        textBold = try values.decodeIfPresent(Int.self, forKey: .textBold) ?? textBold
        textSize = try values.decodeIfPresent(Int.self, forKey: .textSize) ?? textSize
        letterSpacing = try values.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? letterSpacing
        lineSpacingExtra = try values.decodeIfPresent(Int.self, forKey: .lineSpacingExtra) ?? lineSpacingExtra
        titleLineSpacingExtra = try values.decodeIfPresent(Int.self, forKey: .titleLineSpacingExtra) ?? titleLineSpacingExtra
        paragraphSpacing = try values.decodeIfPresent(Int.self, forKey: .paragraphSpacing) ?? paragraphSpacing
        titleMode = try values.decodeIfPresent(Int.self, forKey: .titleMode) ?? titleMode
        titleSize = try values.decodeIfPresent(Int.self, forKey: .titleSize) ?? titleSize
        titleColor = values.decodeAndroidColor(forKey: .titleColor, default: titleColor)
        splitChapterTitle = try values.decodeIfPresent(Bool.self, forKey: .splitChapterTitle) ?? splitChapterTitle
        titleNumberSize = try values.decodeIfPresent(Int.self, forKey: .titleNumberSize) ?? titleNumberSize
        titleNumberColor = values.decodeAndroidColor(forKey: .titleNumberColor, default: titleNumberColor)
        titleNumberSpacing = try values.decodeIfPresent(Int.self, forKey: .titleNumberSpacing) ?? titleNumberSpacing
        titleTopSpacing = try values.decodeIfPresent(Int.self, forKey: .titleTopSpacing) ?? titleTopSpacing
        titleBottomSpacing = try values.decodeIfPresent(Int.self, forKey: .titleBottomSpacing) ?? titleBottomSpacing
        paragraphIndent = try values.decodeIfPresent(String.self, forKey: .paragraphIndent) ?? paragraphIndent
        underlineMode = try values.decodeIfPresent(Int.self, forKey: .underlineMode) ?? underlineMode
        underlineColor = values.decodeAndroidColor(forKey: .underlineColor, default: underlineColor)
        underlineColorSet = try values.decodeIfPresent(Bool.self, forKey: .underlineColorSet) ?? underlineColorSet
        underlineWidth = try values.decodeIfPresent(Double.self, forKey: .underlineWidth) ?? underlineWidth
        underlineDistance = try values.decodeIfPresent(Double.self, forKey: .underlineDistance) ?? underlineDistance
        underlineBodyEnabled = try values.decodeIfPresent(Bool.self, forKey: .underlineBodyEnabled) ?? underlineBodyEnabled
        underlineTitleEnabled = try values.decodeIfPresent(Bool.self, forKey: .underlineTitleEnabled) ?? underlineTitleEnabled
        underlineConfigVersion = try values.decodeIfPresent(Int.self, forKey: .underlineConfigVersion) ?? underlineConfigVersion
        reviewIconColor = values.decodeAndroidColor(forKey: .reviewIconColor, default: reviewIconColor)
        reviewIconSvg = try values.decodeIfPresent(String.self, forKey: .reviewIconSvg) ?? reviewIconSvg
        reviewIconSvgTemplates = try values.decodeIfPresent([ReviewIconSvgTemplate].self, forKey: .reviewIconSvgTemplates) ?? reviewIconSvgTemplates
        reviewIconScale = try values.decodeIfPresent(Int.self, forKey: .reviewIconScale) ?? reviewIconScale
        paddingBottom = try values.decodeIfPresent(Int.self, forKey: .paddingBottom) ?? paddingBottom
        paddingLeft = try values.decodeIfPresent(Int.self, forKey: .paddingLeft) ?? paddingLeft
        paddingRight = try values.decodeIfPresent(Int.self, forKey: .paddingRight) ?? paddingRight
        paddingTop = try values.decodeIfPresent(Int.self, forKey: .paddingTop) ?? paddingTop
        headerPaddingBottom = try values.decodeIfPresent(Int.self, forKey: .headerPaddingBottom) ?? headerPaddingBottom
        headerPaddingLeft = try values.decodeIfPresent(Int.self, forKey: .headerPaddingLeft) ?? headerPaddingLeft
        headerPaddingRight = try values.decodeIfPresent(Int.self, forKey: .headerPaddingRight) ?? headerPaddingRight
        headerPaddingTop = try values.decodeIfPresent(Int.self, forKey: .headerPaddingTop) ?? headerPaddingTop
        footerPaddingBottom = try values.decodeIfPresent(Int.self, forKey: .footerPaddingBottom) ?? footerPaddingBottom
        footerPaddingLeft = try values.decodeIfPresent(Int.self, forKey: .footerPaddingLeft) ?? footerPaddingLeft
        footerPaddingRight = try values.decodeIfPresent(Int.self, forKey: .footerPaddingRight) ?? footerPaddingRight
        footerPaddingTop = try values.decodeIfPresent(Int.self, forKey: .footerPaddingTop) ?? footerPaddingTop
        showHeaderLine = try values.decodeIfPresent(Bool.self, forKey: .showHeaderLine) ?? showHeaderLine
        showFooterLine = try values.decodeIfPresent(Bool.self, forKey: .showFooterLine) ?? showFooterLine
        tipHeaderLeft = try values.decodeIfPresent(Int.self, forKey: .tipHeaderLeft) ?? tipHeaderLeft
        tipHeaderMiddle = try values.decodeIfPresent(Int.self, forKey: .tipHeaderMiddle) ?? tipHeaderMiddle
        tipHeaderRight = try values.decodeIfPresent(Int.self, forKey: .tipHeaderRight) ?? tipHeaderRight
        tipFooterLeft = try values.decodeIfPresent(Int.self, forKey: .tipFooterLeft) ?? tipFooterLeft
        tipFooterMiddle = try values.decodeIfPresent(Int.self, forKey: .tipFooterMiddle) ?? tipFooterMiddle
        tipFooterRight = try values.decodeIfPresent(Int.self, forKey: .tipFooterRight) ?? tipFooterRight
        tipHeaderLeftTemplate = try values.decodeIfPresent(String.self, forKey: .tipHeaderLeftTemplate) ?? tipHeaderLeftTemplate
        tipHeaderMiddleTemplate = try values.decodeIfPresent(String.self, forKey: .tipHeaderMiddleTemplate) ?? tipHeaderMiddleTemplate
        tipHeaderRightTemplate = try values.decodeIfPresent(String.self, forKey: .tipHeaderRightTemplate) ?? tipHeaderRightTemplate
        tipFooterLeftTemplate = try values.decodeIfPresent(String.self, forKey: .tipFooterLeftTemplate) ?? tipFooterLeftTemplate
        tipFooterMiddleTemplate = try values.decodeIfPresent(String.self, forKey: .tipFooterMiddleTemplate) ?? tipFooterMiddleTemplate
        tipFooterRightTemplate = try values.decodeIfPresent(String.self, forKey: .tipFooterRightTemplate) ?? tipFooterRightTemplate
        tipTextSize = try values.decodeIfPresent(Int.self, forKey: .tipTextSize) ?? tipTextSize
        tipColor = values.decodeAndroidColor(forKey: .tipColor, default: tipColor)
        tipDividerColor = values.decodeAndroidColor(forKey: .tipDividerColor, default: tipDividerColor)
        headerMode = try values.decodeIfPresent(Int.self, forKey: .headerMode) ?? headerMode
        footerMode = try values.decodeIfPresent(Int.self, forKey: .footerMode) ?? footerMode
    }

    public static func bundledStyles() throws -> [Self] {
        guard let url = Bundle.module.url(forResource: "reader-presets", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "reader-presets.json"])
        }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }

    public static func importThemes(_ data: Data, onFallback: ((Int, Error) -> Void)? = nil) throws -> [Self] {
        let document = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let items: [Any]
        if let array = document as? [Any] { items = array }
        else if document is [String: Any] { items = [document] }
        else { throw ReaderThemeImportError(issues: ["根节点应为样式对象或数组"]) }
        if items.isEmpty { return [] }
        let decoder = JSONDecoder()
        var themes: [Self] = []
        var issues: [String] = []
        var presets: [Self]?
        for (index, item) in items.enumerated() {
            do {
                let encoded = try JSONSerialization.data(withJSONObject: item, options: [.fragmentsAllowed])
                themes.append(try decoder.decode(Self.self, from: encoded))
            } catch {
                issues.append(Self.importIssue(error, index: index))
                onFallback?(index, error)
                if presets == nil { presets = try bundledStyles() }
                guard let presets, !presets.isEmpty else { throw ReaderThemeImportError(issues: issues) }
                themes.append(presets[index % presets.count])
            }
        }
        guard issues.count < items.count else { throw ReaderThemeImportError(issues: issues) }
        return themes
    }

    private static func importIssue(_ error: Error, index: Int) -> String {
        let path: [CodingKey]
        switch error {
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context): path = context.codingPath
        case DecodingError.keyNotFound(let key, let context): path = context.codingPath + [key]
        default: path = []
        }
        let field = path.map { $0.intValue.map { "[\($0)]" } ?? "." + $0.stringValue }.joined()
        return "[\(index)]\(field)：数据格式不正确"
    }

    public static func exportThemes(_ themes: [Self]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(themes)
    }
}

public struct ReviewIconSvgTemplate: Codable, Equatable, Sendable {
    public var name: String = ""
    public var svg: String = ""
    public init() {}
}

public struct ReaderThemeImportError: LocalizedError {
    public let issues: [String]
    public var errorDescription: String? { "阅读样式导入失败：" + issues.joined(separator: "；") }
    public var recoverySuggestion: String? { "请检查样式文件中的字段格式，或重新导出样式后导入。" }
}

extension KeyedDecodingContainer {
    func decodeAndroidColor(forKey key: Key, default fallback: Int) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return fallback }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            let hex = value.dropFirst()
            guard [6, 8].contains(hex.count), hex.utf8.allSatisfy({
                (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }), let bits = UInt32(hex, radix: 16) else { return fallback }
            return Int(Int32(bitPattern: hex.count == 6 ? bits | 0xFF000000 : bits))
        }
        guard let number = Int64(value), number >= Int64(Int32.min), number <= Int64(UInt32.max) else { return fallback }
        return Int(Int32(bitPattern: UInt32(truncatingIfNeeded: number)))
    }
}
