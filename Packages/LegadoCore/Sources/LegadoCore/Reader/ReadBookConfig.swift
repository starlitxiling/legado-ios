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
        titleColor = try values.decodeIfPresent(Int.self, forKey: .titleColor) ?? titleColor
        splitChapterTitle = try values.decodeIfPresent(Bool.self, forKey: .splitChapterTitle) ?? splitChapterTitle
        titleNumberSize = try values.decodeIfPresent(Int.self, forKey: .titleNumberSize) ?? titleNumberSize
        titleNumberColor = try values.decodeIfPresent(Int.self, forKey: .titleNumberColor) ?? titleNumberColor
        titleNumberSpacing = try values.decodeIfPresent(Int.self, forKey: .titleNumberSpacing) ?? titleNumberSpacing
        titleTopSpacing = try values.decodeIfPresent(Int.self, forKey: .titleTopSpacing) ?? titleTopSpacing
        titleBottomSpacing = try values.decodeIfPresent(Int.self, forKey: .titleBottomSpacing) ?? titleBottomSpacing
        paragraphIndent = try values.decodeIfPresent(String.self, forKey: .paragraphIndent) ?? paragraphIndent
        underlineMode = try values.decodeIfPresent(Int.self, forKey: .underlineMode) ?? underlineMode
        underlineColor = try values.decodeIfPresent(Int.self, forKey: .underlineColor) ?? underlineColor
        underlineColorSet = try values.decodeIfPresent(Bool.self, forKey: .underlineColorSet) ?? underlineColorSet
        underlineWidth = try values.decodeIfPresent(Double.self, forKey: .underlineWidth) ?? underlineWidth
        underlineDistance = try values.decodeIfPresent(Double.self, forKey: .underlineDistance) ?? underlineDistance
        underlineBodyEnabled = try values.decodeIfPresent(Bool.self, forKey: .underlineBodyEnabled) ?? underlineBodyEnabled
        underlineTitleEnabled = try values.decodeIfPresent(Bool.self, forKey: .underlineTitleEnabled) ?? underlineTitleEnabled
        underlineConfigVersion = try values.decodeIfPresent(Int.self, forKey: .underlineConfigVersion) ?? underlineConfigVersion
        reviewIconColor = try values.decodeIfPresent(Int.self, forKey: .reviewIconColor) ?? reviewIconColor
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
        tipColor = try values.decodeIfPresent(Int.self, forKey: .tipColor) ?? tipColor
        tipDividerColor = try values.decodeIfPresent(Int.self, forKey: .tipDividerColor) ?? tipDividerColor
        headerMode = try values.decodeIfPresent(Int.self, forKey: .headerMode) ?? headerMode
        footerMode = try values.decodeIfPresent(Int.self, forKey: .footerMode) ?? footerMode
    }

    public static func importThemes(_ data: Data) throws -> [Self] {
        let decoder = JSONDecoder()
        if let themes = try? decoder.decode([Self].self, from: data) { return themes }
        return [try decoder.decode(Self.self, from: data)]
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
