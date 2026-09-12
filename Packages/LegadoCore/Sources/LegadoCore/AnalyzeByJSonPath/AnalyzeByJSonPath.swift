import Foundation
import CoreFoundation

/// 规格 §4、§11；单条 JSONPath 求值，组合规则由 AnalyzeRule 处理。
public struct AnalyzeByJSonPath: SelectorEngine {
    private let root: Any?

    public init() { root = nil }

    public init(_ content: Any) throws {
        if let text = content as? String {
            var parser = JsonPathJSONParser(text)
            root = try parser.parse()
        } else { root = content }
    }

    /// Kotlin AnalyzeByJSonPath.kt:128-130：对象入口不吞求值异常。
    public func getObject(_ rule: String) throws -> Any {
        guard let root else { throw JsonPathError.pathNotFound }
        var parser = JsonPathParser(rule)
        return try JsonPathEvaluator.read(parser.parse(), root: root)
    }

    /// Kotlin AnalyzeByJSonPath.kt:34-59：列表用换行拼接，异常返回空串。
    public func getString(_ rule: String) -> String? {
        guard !rule.isEmpty else { return nil }
        if let template = template(rule) { return template }
        guard let value = try? getObject(rule) else { return "" }
        return (value as? [Any]).map { $0.map(Self.text).joined(separator: "\n") } ?? Self.text(value)
    }

    /// Kotlin AnalyzeByJSonPath.kt:77-106：标量成为一个条目，数组逐项字符串化。
    public func getStringList(_ rule: String) -> [String] {
        guard !rule.isEmpty else { return [] }
        if let template = template(rule) { return [template] }
        guard let value = try? getObject(rule) else { return [] }
        return ((value as? [Any]) ?? [value]).map(Self.text)
    }

    /// Kotlin AnalyzeByJSonPath.kt:132-144：仅数组可转换为对象列表。
    public func getList(_ rule: String) -> [Any]? {
        guard !rule.isEmpty else { return [] }
        return (try? getObject(rule)) as? [Any] ?? []
    }

    public func evaluate(_ rule: String, content: Any, operation: RuleOperation, context: AnalyzeRule) throws -> Any? {
        let parser = try AnalyzeByJSonPath(content)
        switch operation {
        case .string: return parser.getString(rule)
        case .stringList: return parser.getStringList(rule)
        case .element: return try parser.getObject(rule)
        case .elements: return parser.getList(rule)
        }
    }

    private func template(_ rule: String) -> String? {
        let analyzer = RuleAnalyzer(rule, code: true)
        guard let value = try? analyzer.innerRule(start: "{$.", transform: { getString($0) ?? "" }), !value.isEmpty else { return nil }
        return value
    }

    private static func text(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            if ["d", "f"].contains(String(cString: number.objCType)) { return javaDoubleText(number.doubleValue) }
            return number.stringValue
        }
        if let list = value as? [Any] { return "[" + list.map(text).joined(separator: ", ") + "]" }
        if let object = value as? NSDictionary {
            let keys: [Any] = (object as? JsonPathObject)?.orderedKeys ?? object.allKeys
            return "{" + keys.map { key in text(key) + "=" + text(object.object(forKey: key) ?? NSNull()) }.joined(separator: ", ") + "}"
        }
        return String(describing: value)
    }

    private static func javaDoubleText(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value.sign == .minus ? "-Infinity" : "Infinity" }
        let sign = value.sign == .minus ? "-" : ""
        if value == 0 { return sign + "0.0" }
        var decimal = String(abs(value))
        for precision in 1...16 {
            let candidate = String(format: "%.*e", precision, abs(value))
            if Double(candidate) == abs(value) { decimal = candidate; break }
        }
        let parts = decimal.lowercased().split(separator: "e")
        let mantissa = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        var exponent = (parts.count == 2 ? Int(parts[1])! : 0) + mantissa[0].count - 1
        var digits = Array(mantissa.joined())
        while digits.first == "0" { digits.removeFirst(); exponent -= 1 }
        while digits.count > 1, digits.last == "0" { digits.removeLast() }
        if exponent < -3 || exponent >= 7 {
            return sign + String(digits[0]) + "." + (digits.count == 1 ? "0" : String(digits.dropFirst())) + "E" + String(exponent)
        }
        let point = exponent + 1
        if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + String(digits) }
        if point >= digits.count { return sign + String(digits) + String(repeating: "0", count: point - digits.count) + ".0" }
        return sign + String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
    }
}
