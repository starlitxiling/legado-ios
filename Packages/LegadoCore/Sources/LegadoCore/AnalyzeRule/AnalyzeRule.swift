import Foundation
import SwiftSoup

/// 规格 §2、§4、§8：有状态规则求值器；选择器与变量宿主通过协议注入。
public final class AnalyzeRule {
    var scriptSession: JsSession?
    var scriptBaseUrl: String?
    /// 规格 §4：当前整份内容；内插子规则与 @put 均以此为输入。
    public private(set) var content: Any?
    /// 规格 §2.1：对象入口冒号规则设置的黏性状态。
    public private(set) var isRegex = false
    /// 规格 §2.2：setContent 时根据文本首尾判断的 JSON 特征。
    public private(set) var isJSON = false
    private let engines: [RuleMode: any SelectorEngine]
    private let chapter: (any RuleVariableStorage)?
    private let book: (any RuleVariableStorage)?
    private let ruleData: (any RuleVariableStorage)?
    private let source: (any RuleVariableStorage)?
    private var locals: [String: String] = [:]
    private var cache: [String: [SourceRule]] = [:]
    private var jsoupDocument: Element?
    private let replacer = RuleReplace()
    private var isURLString = false

    /// 规格 §4、§8：未注入的非正则引擎显式报错；变量只写入提供的宿主。
    public init(content: Any? = nil, engines: [RuleMode: any SelectorEngine] = [:],
                chapter: (any RuleVariableStorage)? = nil, book: (any RuleVariableStorage)? = nil,
                ruleData: (any RuleVariableStorage)? = nil, source: (any RuleVariableStorage)? = nil) {
        self.engines = engines
        self.chapter = chapter
        self.book = book
        self.ruleData = ruleData
        self.source = source
        setContent(content)
    }

    /// 规格 §2.2：首尾括号判 JSON；更换内容不重置 isRegex 或已编译字符串规则。
    public func setContent(_ value: Any?) {
        jsoupDocument = nil
        content = value is NSNull ? nil : value
        let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isJSON = (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]"))
    }

    /// 规格 §8.2：本地空值仍会遮蔽宿主变量；nil 移除绑定。
    public func setLocal(_ key: String, value: String?) { locals[key] = value }

    /// 规格 §9.1：只向脚本暴露列出的局部绑定，实体暂提供名称骨架。
    var scriptBindings: [String: Any] {
        var values: [String: Any] = ["src": content ?? NSNull(),
            "book": book.map { ["name": $0.name] as Any } ?? NSNull(),
            "chapter": chapter.map { ["title": $0.name] as Any } ?? NSNull(),
            "source": source.map { ["name": $0.name] as Any } ?? NSNull(),
            "title": chapter.map { $0.name as Any } ?? NSNull()]
        for key in ["paraIndex", "paraData", "page"] {
            if let value = locals[key] { values[key] = key == "page" ? Int32(value).map { $0 as Any } ?? value : value }
        }
        return values
    }

    /// 规格 §8.2：名称优先于变量；宿主空串继续向下查找。
    public func get(_ key: String) -> String {
        if let value = locals[key] { return value }
        if key == "bookName", let book { return book.name }
        if key == "title", let chapter { return chapter.name }
        for store in [chapter, book, ruleData, source] {
            if let value = store?.value(for: key), !value.isEmpty { return value }
        }
        return ""
    }

    /// 规格 §8.1：只写入第一个存在的宿主。
    public func put(_ key: String, value: String?) {
        [chapter, book, ruleData, source].compactMap { $0 }.first?.setValue(value, for: key)
    }

    /// 规格 §2.1：JS 与 WebJS 分别扫描全串；冒号仅在对象入口生效。
    public func splitSourceRule(_ rule: String?, allInOne: Bool = false) throws -> [SourceRule] {
        guard let rule, !rule.isEmpty else { return [] }
        var cursor = 0
        if allInOne && rule.hasPrefix(":") { isRegex = true; cursor = 1 }
        let base: RuleMode = isRegex ? .regex : .default
        let text = rule as NSString
        var segments: [SourceRule] = []
        func appendText(_ start: Int, _ end: Int) throws {
            guard end > start else { return }
            let value = asciiTrim(text.substring(with: NSRange(location: start, length: end - start)))
            if !value.isEmpty { segments.append(try SourceRule(value, mode: base, isJSON: isJSON)) }
        }
        let js = try NSRegularExpression(pattern: #"<js>([\w\W]*?)</js>|@js:([\w\W]*)"#, options: .caseInsensitive)
        for match in js.matches(in: rule, range: NSRange(location: 0, length: text.length)) {
            try appendText(cursor, match.range.location)
            let range = match.range(at: 2).location == NSNotFound ? match.range(at: 1) : match.range(at: 2)
            segments.append(try SourceRule(text.substring(with: range), mode: .js, isJSON: isJSON))
            cursor = NSMaxRange(match.range)
        }
        let web = try NSRegularExpression(pattern: #"@webjs:([\w\W]{5,})"#, options: .caseInsensitive)
        for match in web.matches(in: rule, range: NSRange(location: 0, length: text.length)) {
            try appendText(cursor, match.range.location)
            segments.append(try SourceRule(text.substring(with: match.range(at: 1)), mode: .webJS, isJSON: isJSON))
            cursor = NSMaxRange(match.range)
        }
        try appendText(cursor, text.length)
        return segments
    }

    /// 规格 §4：默认执行 HTML4 反转义；URL 后处理留给宿主集成层。
    public func getString(_ rule: String?, unescape: Bool = true, content replacementContent: Any? = nil, isURL: Bool = false) throws -> String {
        let previous = isURLString
        isURLString = isURL
        defer { isURLString = previous }
        let result = try evaluate(cached(rule), operation: .string, content: replacementContent)
        let text = result == nil || result is NSNull ? "" : ruleText(result)
        return unescape ? try HTML4Entities.unescape(text) : text
    }

    /// 规格 §4：字符串按换行拆列表，空规则或非列表结果返回 nil。
    public func getStringList(_ rule: String?) throws -> [String]? {
        let value = try evaluate(cached(rule), operation: .stringList)
        if let text = value as? String { return text.components(separatedBy: "\n") }
        return value as? [String]
    }

    /// 规格 §4：单对象入口支持模板与替换。
    public func getElement(_ rule: String?) throws -> Any? {
        try evaluate(splitSourceRule(rule, allInOne: true), operation: .element)
    }

    /// 规格 §4、§11：对象列表不调用 makeUpRule，归一时去除 null。
    public func getElements(_ rule: String?) throws -> [Any] {
        let value = try evaluate(splitSourceRule(rule, allInOne: true), operation: .elements)
        return (value as? [Any])?.filter { !($0 is NSNull) } ?? []
    }

    func evaluateScript(_ script: String, result: Any?) throws -> Any? {
        let previous = scriptSession
        defer { scriptSession = previous }
        return try engine(.js).evaluate(script, content: result ?? NSNull(), operation: .string, context: self)
    }

    func evaluateEmbeddedRule(_ rule: String) throws -> String {
        let segments: [SourceRule]
        if let cached = cache[rule] { segments = cached }
        else {
            segments = [try SourceRule(rule, isJSON: isJSON)]
            if cache.count < 16 { cache[rule] = segments }
        }
        let value = try evaluate(segments, operation: .string)
        return try HTML4Entities.unescape(value == nil || value is NSNull ? "" : ruleText(value))
    }

    private func cached(_ rule: String?) throws -> [SourceRule] {
        guard let rule, !rule.isEmpty else { return [] }
        if let value = cache[rule] { return value }
        let value = try splitSourceRule(rule)
        cache[rule] = value
        return value
    }

    /// 规格 §11：原始字符串内容共享 DOM；中间结果独立解析，原节点保持身份。
    func jsoupRoot(for value: Any) throws -> Element {
        guard let text = value as? String, let original = content as? String, text == original else {
            return try AnalyzeByJSoup.parse(value)
        }
        if let jsoupDocument { return jsoupDocument }
        let document = try AnalyzeByJSoup.parse(text)
        jsoupDocument = document
        return document
    }

    private func engine(_ mode: RuleMode) -> any SelectorEngine {
        engines[mode] ?? (mode == .regex ? AnalyzeByRegex() as any SelectorEngine : UnsupportedSelectorEngine(mode: mode))
    }

    private func evaluate(_ segments: [SourceRule], operation: RuleOperation, content replacementContent: Any? = nil) throws -> Any? {
        guard let content = replacementContent is NSNull ? self.content : replacementContent ?? self.content, !segments.isEmpty else { return nil }
        let previousSession = scriptSession
        scriptSession = nil
        defer { scriptSession = previousSession }
        var result: Any? = content
        for segment in segments {
            for key in segment.putMap.keys.sorted() { put(key, value: try getString(segment.putMap[key])) }
            let replacement = operation == .elements ? nil : try segment.makeUpRule(result, context: self)
            guard let current = result, !(current is NSNull) else { continue }
            let rule = replacement?.rule ?? segment.rule
            let shouldEvaluate: Bool
            switch operation {
            case .string: shouldEvaluate = !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement?.pattern.isEmpty != false
            case .stringList: shouldEvaluate = !rule.isEmpty
            case .element, .elements: shouldEvaluate = true
            }
            if shouldEvaluate {
                let value = try dispatch(rule, mode: segment.mode, content: current, operation: operation)
                result = value is NSNull ? nil : value
            }
            if let replacement, !replacement.pattern.isEmpty {
                if operation == .stringList, let list = JsEngine.nativeValue(result) as? [Any] { result = list.map { replacer.apply(ruleText($0), replacement: replacement) } }
                else if result != nil || operation != .string { result = replacer.apply(ruleText(result), replacement: replacement) }
            }
        }
        return JsEngine.nativeValue(result)
    }

    private func dispatch(_ rule: String, mode: RuleMode, content: Any, operation: RuleOperation) throws -> Any? {
        if isURLString && mode == .default && operation == .string {
            return (try dispatch(rule, mode: mode, content: content, operation: .stringList) as? [String])?.first
        }
        let selector = engine(mode)
        if mode == .js { return try selector.evaluate(rule, content: content, operation: .string, context: self) }
        let content = JsEngine.nativeValue(content) ?? NSNull()
        if mode == .webJS {
            let value = try selector.evaluate(rule, content: content, operation: .string, context: self)
            guard let text = value as? String else { return nil }
            let json = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
            switch operation {
            case .string: return text
            case .stringList: return (json as? [String]).map { $0 as Any } ?? text
            case .element: return json as? [String: Any]
            case .elements: return json as? [[String: Any]]
            }
        }
        if operation == .element, mode == .default || mode == .xpath {
            return try selector.evaluate(rule, content: content, operation: .elements, context: self)
        }
        guard [.default, .xpath, .json].contains(mode), operation == .string || operation == .stringList else {
            return try selector.evaluate(rule, content: content, operation: operation, context: self)
        }
        let isCSS = mode == .default && rule.lowercased().hasPrefix("@css:")
        let elementsRule = isCSS ? asciiTrim(String(rule.dropFirst(5))) : rule
        let analyzer = RuleAnalyzer(elementsRule, code: mode == .json)
        let separators = operation == .string && mode != .default ? ["&&", "||"] : ["&&", "||", "%%"]
        let rules = try analyzer.splitRule(separators: separators)
        if rules.count == 1 {
            if mode == .default {
                return try selector.evaluate(elementsRule, content: content, operation: operation, isCSS: isCSS, context: self)
            }
            return try selector.evaluate(rule, content: content, operation: operation, context: self)
        }
        var lists: [[String]] = []
        for subrule in rules {
            let entryOperation: RuleOperation = operation == .string && mode != .default ? .string : .stringList
            let value: Any?
            if mode == .json || mode == .xpath {
                value = try dispatch(subrule, mode: mode, content: content, operation: entryOperation)
            } else {
                value = try selector.evaluate(subrule, content: content, operation: entryOperation, isCSS: isCSS, context: self)
            }
            let list = (value as? [String]) ?? (value as? String).map { $0.isEmpty ? [] : [$0] } ?? []
            if !list.isEmpty { lists.append(list) }
            if analyzer.elementsType == "||", !list.isEmpty { break }
        }
        var combined: [String] = []
        if analyzer.elementsType == "%%", let first = lists.first {
            for index in first.indices { for list in lists where index < list.count { combined.append(list[index]) } }
        } else { combined = lists.flatMap { $0 } }
        if operation == .string {
            return mode == .default && combined.isEmpty ? nil : combined.joined(separator: "\n")
        }
        return combined
    }
}
