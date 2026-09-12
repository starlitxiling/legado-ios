import Foundation
import CoreFoundation
import JavaScriptCore

/// 规格 §2.2、§4：规则段的六种模式。
public enum RuleMode: String, Hashable {
    case xpath = "XPath", json = "Json", `default` = "Default"
    case js = "Js", regex = "Regex", webJS = "WebJs"
}

/// 规格 §4：选择器入口保留字符串与对象的区别。
public enum RuleOperation { case string, stringList, element, elements }

/// 规格 §4：外部选择器只求值一个子规则；字符串列表合并由 AnalyzeRule 承担。
public protocol SelectorEngine {
    /// 规格 §4：脚本引擎经 string 返回原值，Default/XPath 的 element 经 elements 调用。
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any?
    /// 规格 §5.2、§6：组合子项共享整段 CSS 模式，rule 不含整段 @CSS: 前缀。
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, isCSS: Bool, context: AnalyzeRule) throws -> Any?
}

public extension SelectorEngine {
    /// 规格 §5.2：保持已有引擎兼容，通过原生前缀显式传递 CSS 模式。
    func evaluate(_ rule: String, content: Any, operation: RuleOperation, isCSS: Bool, context: AnalyzeRule) throws -> Any? {
        // 非 CSS 段的子项不能单独启用 CSS；额外 @ 阻止前缀识别，并由旧式 trim 消费。
        let forwarded = isCSS ? "@CSS:" + rule : rule.lowercased().hasPrefix("@css:") ? "@" + rule : rule
        return try evaluate(forwarded, content: content, operation: operation, context: context)
    }
}

/// 规格 §4、§7：尚未提供的引擎与无效正则显式失败。
public enum RuleEvaluationError: Error, Equatable {
    case unsupported(RuleMode)
    case emptyRegex
    case unmatchedCapture(Int)
    case invalidReplacement
}

/// 规格 §4、§5.2：未安装引擎的桩；仅实现无需解析文档的空 JSoup 列表规则。
public struct UnsupportedSelectorEngine: SelectorEngine {
    /// 规格 §4：缺失引擎的模式，用于显式错误报告。
    public let mode: RuleMode
    /// 规格 §4：创建指定模式的未支持桩。
    public init(mode: RuleMode) { self.mode = mode }
    /// 规格 §4、§5.2：仅空 Default 字符串列表无需引擎即可确定。
    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        if mode == .default, operation == .stringList, rule.isEmpty { return [String]() }
        throw RuleEvaluationError.unsupported(mode)
    }
}

/// 规格 §8：宿主可注入持久化存储；nil 写入表示删除。
public protocol RuleVariableStorage: AnyObject {
    /// 规格 §8.2：书名或章节标题；空串仍遮蔽同名变量。
    var name: String { get }
    /// 规格 §8.2：读取原值，保留缺失与空串的区别。
    func value(for key: String) -> String?
    /// 规格 §8.1：宿主负责持久化、大变量存储与 nil 删除。
    func setValue(_ value: String?, for key: String)
}

/// 规格 §8：内存变量容器，可在多个解析器之间共享。
public final class RuleVariableStore: RuleVariableStorage {
    /// 规格 §8.2：可变实体名称。
    public var name: String
    /// 规格 §8：当前内存变量快照。
    public private(set) var variables: [String: String]
    /// 规格 §8：以初始变量与实体名称创建内存宿主。
    public init(_ variables: [String: String] = [:], name: String = "") {
        self.variables = variables
        self.name = name
    }
    /// 规格 §8.2：保留空串和不存在的区别。
    public func value(for key: String) -> String? { variables[key] }
    /// 规格 §8.1：nil 删除键，其余写入原值。
    public func setValue(_ value: String?, for key: String) { variables[key] = value }
}

func ruleText(_ value: Any?) -> String {
    if let value = value as? JSValue { return ruleText(JsEngine.nativeValue(value)) }
    guard let value, !(value is NSNull) else { return "null" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
    if let list = value as? [Any] { return "[" + list.map { ruleText($0) }.joined(separator: ", ") + "]" }
    return String(describing: value)
}

func integralScriptNumber(_ value: Any?) -> Double? {
    if let value = value as? JSValue { return value.isNumber ? integralScriptNumber(value.toDouble()) : nil }
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
    guard let number = value as? Double, number.isFinite, number.truncatingRemainder(dividingBy: 1) == 0 else { return nil }
    return number
}

func asciiTrim(_ value: String) -> String {
    String(value.unicodeScalars.drop(while: { $0.value <= 32 }).reversed()
        .drop(while: { $0.value <= 32 }).reversed().map(Character.init))
}
