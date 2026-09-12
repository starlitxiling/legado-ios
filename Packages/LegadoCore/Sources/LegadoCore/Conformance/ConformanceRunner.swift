import Foundation
import SwiftSoup

public enum ConformanceRunner {
    public enum Status: String { case passed, failed, skipped, unsupported }

    public struct Result {
        public let id: String
        public let kind: String
        public let status: Status
        public let actual: ConformanceCase.Expectation?
        public let expected: ConformanceCase.Expectation
        public let detail: String
    }

    public struct Report {
        public let results: [Result]

        public var summary: String {
            Dictionary(grouping: results, by: \.kind).keys.sorted().map { kind in
                let entries = results.filter { $0.kind == kind }
                func count(_ status: Status) -> Int { entries.filter { $0.status == status }.count }
                return "\(kind): supported=\(entries.count - count(.unsupported)), skipped=\(count(.skipped)), passed=\(count(.passed)), failed=\(count(.failed)), unsupported=\(count(.unsupported))"
            }.joined(separator: "\n")
        }
    }

    public static func load(directories: [URL]) throws -> [ConformanceCase] {
        var cases: [ConformanceCase] = []
        for directory in directories {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.path < $1.path }
            for file in files {
                cases += try JSONDecoder().decode([ConformanceCase].self, from: Data(contentsOf: file))
            }
        }
        return cases
    }

    public static func run(_ cases: [ConformanceCase]) -> Report {
        Report(results: cases.map { test in
            let ruleKinds = ["replace", "template", "prefix", "regex", "empty", "jsoup-default", "jsoup-css"]
            let jsOperations = ["RhinoScriptEngine.eval", "AnalyzeRule.evalJS", "AnalyzeRule.get", "AnalyzeRule.getString", "AnalyzeRule.getStringList", "AnalyzeRule.getElement", "AnalyzeRule.getElements"]
            let jsFixture = test.kind == "js" && jsOperations.contains { test.input.variables?["operation"] == .string($0) }
            let ruleFixture = jsFixture || ruleKinds.contains(test.kind) || ["template", "prefix", "empty"].contains { test.id.hasPrefix("synthetic-\($0)-") }
            guard test.kind == "url-options" || ruleFixture else {
                return result(test, status: .unsupported, detail: "本单元尚未实现 kind=\(test.kind)")
            }
            if test.input.variables?["operation"] == .string("ReplacePreview.apply") {
                return result(test, status: .unsupported, detail: "ReplacePreview.apply 是 UI 替换预览，非 AnalyzeRule 的 ## 替换")
            }
            do {
                let actual: ConformanceCase.Expectation
                if test.input.variables?["operation"] == .string("RhinoScriptEngine.eval") {
                    actual = try evaluateJS(test.input)
                } else {
                    actual = try test.kind == "url-options" ? evaluateURL(test.input) : evaluateRule(test.input)
                }
                return result(test, status: actual == test.expect ? .passed : .failed, actual: actual,
                              detail: actual == test.expect ? "" : "期望 \(test.expect)，实际 \(actual)")
            } catch let error as Skip {
                return result(test, status: .skipped, detail: error.reason)
            } catch RuleEvaluationError.unsupported(let mode) {
                return result(test, status: .skipped, detail: "依赖未安装的 \(mode.rawValue) 选择器或脚本引擎")
            } catch UrlOptions.OptionError.illegalArgument {
                let actual = ConformanceCase.Expectation.error("IllegalArgumentException")
                return result(test, status: actual == test.expect ? .passed : .failed, actual: actual,
                              detail: actual == test.expect ? "" : "期望 \(test.expect)，实际 \(actual)")
            } catch {
                return result(test, status: .failed, detail: "执行失败：\(error)")
            }
        })
    }

    private struct Skip: Error { let reason: String }

    private static func jsValue(_ value: ConformanceCase.JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let value): return value
        case .number(let value): return NSDecimalNumber(decimal: value)
        case .string(let value): return value
        case .array(let value): return value.map(jsValue)
        case .object(let value): return value.mapValues(jsValue)
        }
    }

    private static func evaluateJS(_ input: ConformanceCase.Input) throws -> ConformanceCase.Expectation {
        var javaMaps: Set<String> = []
        if case .object(let types) = input.variables?["bindingTypes"] {
            for (key, type) in types {
                guard type == .string("java.util.HashMap") else { throw Skip(reason: "尚未实现宿主绑定类型 \(type)") }
                javaMaps.insert(key)
            }
        }
        var bindings: [String: Any] = [:]
        if case .object(let values) = input.variables?["bindings"] { bindings = values.mapValues(jsValue) }
        let value = try JsEngine().evaluateScript(input.rule, bindings: bindings, javaMapBindings: javaMaps)
        if let list = value as? [String] { return .stringList(list) }
        return .string(ruleText(value))
    }

    /// 规格 §2、§4、§7、§8：保留 fixture 原入口及投影，不用 expect 选择算法。
    private static func evaluateRule(_ input: ConformanceCase.Input) throws -> ConformanceCase.Expectation {
        let variables = input.variables ?? [:]
        func string(_ key: String) -> String? {
            guard case .string(let value) = variables[key] else { return nil }
            return value
        }
        func values(_ key: String) throws -> [String: String]? {
            guard let value = variables[key] else { return nil }
            guard case .object(let object) = value else { throw Skip(reason: "\(key) 需要变量对象") }
            var result: [String: String] = [:]
            for (name, value) in object {
                guard case .string(let text) = value else { throw Skip(reason: "\(key).\(name) 需要字符串值") }
                result[name] = text
            }
            return result
        }
        let operation = string("operation") ?? ""
        let supportedKeys: Set<String> = ["operation", "projection", "locals", "ruleData", "isUrl"]
        if ["getString", "getStringList", "getElements"].contains(operation) || operation.hasPrefix("AnalyzeByJSoup.") {
            return try evaluateJSoup(input)
        }
        if let key = variables.keys.sorted().first(where: { !supportedKeys.contains($0) }) {
            throw Skip(reason: "尚未实现规则 fixture 配置 \(key)")
        }
        let parser = AnalyzeRule(content: input.document, engines: [.default: AnalyzeByJSoup(), .js: JsEngine(baseUrl: input.baseUrl ?? "")],
                                 ruleData: try values("ruleData").map { RuleVariableStore($0) })
        for (key, value) in try values("locals") ?? [:] { parser.setLocal(key, value: value) }
        if variables["isUrl"] == .bool(true), ["AnalyzeRule.getString", "AnalyzeRule.getStringList"].contains(operation) {
            throw Skip(reason: "本单元尚未接入 URL 后处理")
        }
        let projection = string("projection")
        if operation != "AnalyzeRule.getElements" && projection != nil { throw Skip(reason: "该入口尚未实现投影 \(projection!)") }
        switch operation {
        case "AnalyzeRule.evalJS": return .string(ruleText(try parser.evaluateScript(input.rule, result: nil)))
        case "AnalyzeRule.get": return .string(parser.get(input.rule))
        case "AnalyzeRule.getString": return .string(try parser.getString(input.rule))
        case "AnalyzeRule.getStringList":
            guard let result = try parser.getStringList(input.rule) else { throw Skip(reason: "schema 尚无 null 字符串列表结果") }
            return .stringList(result)
        case "AnalyzeRule.getElement":
            let result = try parser.getElement(input.rule)
            if let list = result as? [String] { return .stringList(list) }
            if let string = result as? String { return .string(string) }
            throw Skip(reason: "schema 尚无该对象或 null 结果类型")
        case "AnalyzeRule.getElements":
            let result = try parser.getElements(input.rule)
            if let projection {
                if let elements = result as? [Element], ["id", "text", "outerHtml"].contains(projection) {
                    return .stringList(try projectJSoup(elements, projection))
                }
                guard projection.hasPrefix("["), projection.hasSuffix("]"),
                      let index = Int(projection.dropFirst().dropLast()), index >= 0 else { throw Skip(reason: "尚未实现投影 \(projection)") }
                let values = try result.map { item -> String in
                    guard let groups = item as? [String], index < groups.count else { throw Skip(reason: "投影需要足够长度的正则分组列表") }
                    return groups[index]
                }
                return .stringList(values)
            }
            guard let values = result as? [String] else { throw Skip(reason: "schema 尚无嵌套对象列表结果") }
            return .stringList(values)
        default: throw Skip(reason: "尚未实现规则 operation=\(operation)")
        }
    }

    private static func projectJSoup(_ elements: [Element], _ projection: String) throws -> [String] {
        switch projection {
        case "id": return elements.map { $0.id() }
        case "text": return try elements.map { try $0.text() }
        case "outerHtml": return try elements.map { try $0.outerHtml() }
        default: throw Skip(reason: "尚未实现 DOM 投影 \(projection)")
        }
    }

    /// 规格 §5、§11：同一 DOM 执行 beforeEach 和 repeat，验证每轮输出一致。
    private static func evaluateJSoup(_ input: ConformanceCase.Input) throws -> ConformanceCase.Expectation {
        let variables = input.variables ?? [:]
        let supported: Set<String> = ["operation", "projection", "beforeEach", "repeat"]
        if let key = variables.keys.sorted().first(where: { !supported.contains($0) }) {
            throw Skip(reason: "尚未实现 DOM fixture 配置 \(key)")
        }
        let parser = try AnalyzeByJSoup(input.document ?? NSNull())
        func evaluate(_ operation: String, _ rule: String, projection: String?) throws -> ConformanceCase.Expectation {
            switch operation {
            case "getString", "AnalyzeByJSoup.getString": return .string(try parser.getString(rule) ?? "")
            case "getStringList", "AnalyzeByJSoup.getStringList": return .stringList(try parser.getStringList(rule))
            case "getElements", "AnalyzeByJSoup.getElements":
                let elements = try parser.getElements(rule)
                return .stringList(try projectJSoup(elements, projection ?? "outerHtml"))
            default: throw Skip(reason: "尚未实现 DOM operation=\(operation)")
            }
        }
        guard case .string(let operation) = variables["operation"] else { throw Skip(reason: "DOM fixture 缺少 operation") }
        var projection: String?
        if case .string(let value) = variables["projection"] { projection = value }
        var count = 1
        if case .number(let value) = variables["repeat"] {
            guard value > 0, value <= 1000, Decimal(NSDecimalNumber(decimal: value).intValue) == value else {
                throw Skip(reason: "DOM repeat 需要 1..1000 的整数")
            }
            count = NSDecimalNumber(decimal: value).intValue
        }
        var first: ConformanceCase.Expectation?
        for _ in 0..<count {
            if case .array(let steps) = variables["beforeEach"] {
                for step in steps {
                    guard case .object(let object) = step, case .string(let operation) = object["operation"],
                          case .string(let rule) = object["rule"] else { throw Skip(reason: "DOM beforeEach 需要 operation 和 rule") }
                    _ = try evaluate(operation, rule, projection: nil)
                }
            }
            let value = try evaluate(operation, input.rule, projection: projection)
            if let first, first != value { throw DOMRepeatError.inconsistent }
            first = value
        }
        return first!
    }

    private enum DOMRepeatError: Error { case inconsistent }

    private static func result(_ test: ConformanceCase, status: Status,
                               actual: ConformanceCase.Expectation? = nil, detail: String) -> Result {
        Result(id: test.id, kind: test.kind, status: status, actual: actual, expected: test.expect, detail: detail)
    }

    private static func evaluateURL(_ input: ConformanceCase.Input) throws -> ConformanceCase.Expectation {
        let variables = input.variables ?? [:]
        func string(_ key: String) -> String? {
            guard case .string(let value) = variables[key] else { return nil }
            return value
        }
        let operation = string("operation") ?? ""
        let projection = string("projection")
        switch operation {
        case "parseDnsIpAddresses":
            let addresses = try UrlOptions.parseDnsIpAddresses(input.document ?? "")
            guard projection == "[0].hostAddress" else { throw Skip(reason: "尚未实现 IP 列表投影 \(projection ?? "nil")") }
            return .string(addresses[0])
        case "validateDnsIpProxyCompatibility":
            try UrlOptions.validateDnsIpProxyCompatibility(proxy: string("proxy"), dnsIp: string("dnsIp"))
            throw Skip(reason: "schema 尚无 Unit 成功返回值")
        case "UrlOption", "UrlOption.fromJson":
            var options = operation == "UrlOption.fromJson" ? try UrlOptions.fromJSON(input.document ?? "") : UrlOptions()
            if operation == "UrlOption", case .object(let setters) = variables["setters"] {
                for key in setters.keys.sorted() {
                    let value: String?
                    switch setters[key] {
                    case .string(let text): value = text
                    case .null: value = nil
                    default: throw Skip(reason: "setter \(key) 需要字符串或 null")
                    }
                    switch key {
                    case "setTimeout": options.setTimeout(value)
                    case "setFollowRedirects": options.setFollowRedirects(value)
                    case "setDnsIp": options.setDnsIp(value)
                    default: throw Skip(reason: "尚未实现 setter \(key)")
                    }
                }
            }
            switch input.rule {
            case "getDnsIp": return .string(options.dnsIp ?? "null")
            default: throw Skip(reason: "尚未实现 getter \(input.rule)")
            }
        case "AnalyzeUrl":
            var rule = input.rule
            if rule.lowercased().contains("<js>") || rule.lowercased().contains("@js:") {
                throw Skip(reason: "URL JS 切段流水线尚未接入")
            }
            if rule.contains("{{") && rule.contains("}}") {
                let urlKeys: Set<String> = ["page", "key", "speakText", "speakSpeed", "book", "source", "infoMap", "extraParams"]
                let bindings = variables.filter { urlKeys.contains($0.key) }.mapValues(jsValue)
                rule = try JsEngine(baseUrl: input.baseUrl ?? "").interpolateURL(rule, bindings: bindings)
            }
            let parsed = UrlOptions.parse(rule)
            let options = parsed.options
            if options.js != nil { throw Skip(reason: "选项 js 会执行脚本并改写 URL；本单元不执行 JavaScript") }
            switch projection {
            case "url":
                if input.baseUrl != nil || rule.contains("<") { throw Skip(reason: "URL 绝对化或分页替换属于后续阶段") }
                return .string(parsed.url)
            case "method": return .string(options.method)
            case "charset": return .string(options.charset ?? "null")
            case "body": return .string(options.body ?? "null")
            case "retry.toString": return .string(String(options.retry))
            case "useWebView.toString": return .string(String(options.useWebView))
            case "derivedCallTimeoutMillis(readTimeoutMs).toString":
                guard let timeout = options.callTimeout else { throw Skip(reason: "未提供 readTimeoutMs；无法派生 callTimeout") }
                return .string(String(timeout))
            default:
                if let projection, projection.hasPrefix("headerMap["), projection.hasSuffix("]") {
                    let key = String(projection.dropFirst(10).dropLast())
                    return .string(options.headers[key] ?? "null")
                }
                throw Skip(reason: "尚未实现 URL 投影 \(projection ?? "nil")")
            }
        default: throw Skip(reason: "尚未实现 operation=\(operation)")
        }
    }
}
