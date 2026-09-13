import Foundation
import GRDB

public struct TxtTocRule: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable, Identifiable {
    public static let databaseTableName = "txtTocRules"
    public var id: Int64
    public var name: String
    public var rule: String
    public var replacement: String = ""
    public var example: String?
    public var serialNumber: Int
    public var enable: Bool

    public init(id: Int64, name: String, rule: String, replacement: String = "", example: String? = nil,
                serialNumber: Int = 0, enable: Bool = true) {
        self.id = id; self.name = name; self.rule = rule; self.replacement = replacement
        self.example = example; self.serialNumber = serialNumber; self.enable = enable
    }

    public func validate() throws { _ = try NSRegularExpression(pattern: rule, options: [.anchorsMatchLines]) }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(Int64.self, forKey: .id) ?? GsonDecoding.time(from: decoder)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        rule = try values.decodeIfPresent(String.self, forKey: .rule) ?? ""
        replacement = try values.decodeIfPresent(String.self, forKey: .replacement) ?? ""
        example = try values.decodeIfPresent(String.self, forKey: .example)
        serialNumber = try values.decodeIfPresent(Int.self, forKey: .serialNumber) ?? -1
        enable = try values.decodeIfPresent(Bool.self, forKey: .enable) ?? true
    }
    public static let builtIn: [TxtTocRule] = [
        .init(id: -1, name: "目录(去空白)", rule: #"(?<=[　\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$"#, example: "第一章 假装第一章前面有空白但我不要", serialNumber: 0, enable: true),
        .init(id: -2, name: "目录", rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$"#, example: "第一章 标准的粤语就是这样", serialNumber: 1, enable: true),
        .init(id: -3, name: "目录(匹配简介)", rule: #"(?<=[　\s])(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$"#, example: "简介 老夫诸葛村夫", serialNumber: 2, enable: false),
        .init(id: -4, name: "目录(古典、轻小说备用)", rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$"#, example: "第一章 比上面只多了回和话", serialNumber: 3, enable: false),
        .init(id: -5, name: "数字(纯数字标题)", rule: #"(?<=[　\s])\d+\.?[ 　\t]{0,4}$"#, example: "12", serialNumber: 4, enable: false),
        .init(id: -6, name: "大写数字(纯数字标题)", rule: #"(?<=[　\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,12}[ 　\t]{0,4}$"#, example: "一百七十", serialNumber: 5, enable: false),
        .init(id: -7, name: "数字混合(纯数字标题)", rule: #"(?<=[　\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]{1,12}[ 　\t]{0,4}$"#, example: "12\n一百七十", serialNumber: 6, enable: false),
        .init(id: -8, name: "数字 分隔符 标题名称", rule: #"^[ 　\t]{0,4}\d{1,5}[:：,.， 、_—\-].{1,30}$"#, example: "1、这个就是标题", serialNumber: 7, enable: true),
        .init(id: -9, name: "大写数字 分隔符 标题名称", rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\-].{1,30}$"#, example: "一、只有前面的数字有差别\n二十四章 我瞎编的标题", serialNumber: 8, enable: true),
        .init(id: -10, name: "数字混合 分隔符 标题名称", rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?[ 、_—\-]|\d{1,5}章?[:：,.， 、_—\-]).{0,30}$"#, example: "1、人参公鸡\n二百二十章 boy next door", serialNumber: 9, enable: false),
        .init(id: -11, name: "正文 标题/序号", rule: #"^[ 　\t]{0,4}正文[ 　]{1,4}.{0,20}$"#, example: "正文 我奶常山赵子龙", serialNumber: 10, enable: true),
        .init(id: -12, name: "Chapter/Section/Part/Episode 序号 标题", rule: #"^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,30}$"#, example: "Chapter 1 MyGrandmaIsNB", serialNumber: 11, enable: true),
        .init(id: -13, name: "Chapter(去简介)", rule: #"^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][Oo]\.|[Ee]pisode)\s{0,4}\d{1,4}.{0,30}$"#, example: "Chapter 1 MyGrandmaIsNB", serialNumber: 12, enable: false),
        .init(id: -14, name: "特殊符号 序号 标题", rule: #"(?<=[\s　])[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$"#, example: "【第一章 后面的符号可以没有", serialNumber: 13, enable: true),
        .init(id: -15, name: "特殊符号 标题(成对)", rule: #"(?<=[\s　]{0,4})(?:[\[〈「『〖〔《（【\(].{1,30}[\)】）》〕〗』」〉\]]?|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$"#, example: "『加个直角引号更专业』\n(11)我奶常山赵子聋", serialNumber: 14, enable: false),
        .init(id: -16, name: "特殊符号 标题(单个)", rule: #"(?<=[\s　]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$"#, example: "☆、晋江作者最喜欢的格式", serialNumber: 15, enable: true),
        .init(id: -17, name: "章/卷 序号 标题", rule: #"^[ \t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$"#, example: "卷五 开源盛世", serialNumber: 16, enable: true),
        .init(id: -18, name: "顶格标题", rule: #"^\S.{1,20}$"#, example: "20字以内顶格写的都是标题", serialNumber: 17, enable: false),
        .init(id: -19, name: "双标题(前向)", rule: #"(?m)(?<=[ \t　]{0,4})第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$(?=[\s　]{0,8}第[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章)"#, example: "第一章 真正的标题\n第一章 这个不要", serialNumber: 18, enable: false),
        .init(id: -20, name: "双标题(后向)", rule: #"(?m)(?<=[ \t　]{0,4}第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$[\s　]{0,8})第[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$"#, example: "第一章 这个标题不要\n第一章真正的标题", serialNumber: 19, enable: false),
        .init(id: -21, name: "书名 括号 序号", rule: #"^[一-龥]{1,20}[ 　\t]{0,4}[(（][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\t]{0,4}$"#, example: "标题后面数字有括号(12)", serialNumber: 20, enable: true),
        .init(id: -22, name: "书名 序号", rule: #"^[一-龥]{1,20}[ 　\t]{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\t]{0,4}$"#, example: "标题后面数字没有括号124", serialNumber: 21, enable: true),
        .init(id: -23, name: "特定字符 标题 特定符号", rule: #"(?<=\={3,6}).{1,40}?(?=\=)"#, example: "===起这种标题干什么===", serialNumber: 22, enable: false),
        .init(id: -24, name: "字数分割 分节阅读", rule: #"(?<=[ 　\t]{0,4})(?:.{0,15}分[页节章段]阅读[-_ ]|第\s{0,4}[\d零一二两三四五六七八九十百千万]{1,6}\s{0,4}[页节]).{0,30}$"#, example: "分节|分页|分段阅读\n第一页", serialNumber: 23, enable: true),
        .init(id: -25, name: "通用规则", rule: #"(?im)^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$|^.{0,6}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-z]{1,8}[、. 　].{0,20}$"#, example: "激进规则,适配更多非常用格式", serialNumber: 24, enable: false),
        .init(id: -100, name: "默认分章规则", rule: #""#, example: "兜底规则，请勿改动此内容", serialNumber: 99, enable: false),
    ]
}
