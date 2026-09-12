import Foundation

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
            let ruleKinds = ["replace", "template", "prefix", "regex", "empty"]
            let ruleFixture = ruleKinds.contains(test.kind) || ["template", "prefix", "empty"].contains { test.id.hasPrefix("synthetic-\($0)-") }
            guard test.kind == "url-options" || ruleFixture else {
                return result(test, status: .unsupported, detail: "本单元尚未实现 kind=\(test.kind)")
            }
            do {
                let actual = try test.kind == "url-options" ? evaluateURL(test.input) : evaluateRule(test.input)
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
        if operation == "ReplacePreview.apply" { throw Skip(reason: "ReplacePreview.apply 是 UI 替换预览，非 AnalyzeRule 的 ## 替换") }
        let supportedKeys: Set<String> = ["operation", "projection", "locals", "ruleData"]
        if let key = variables.keys.sorted().first(where: { !supportedKeys.contains($0) }) {
            throw Skip(reason: "尚未实现规则 fixture 配置 \(key)")
        }
        let parser = AnalyzeRule(content: input.document, ruleData: try values("ruleData").map { RuleVariableStore($0) })
        for (key, value) in try values("locals") ?? [:] { parser.setLocal(key, value: value) }
        if input.baseUrl != nil { throw Skip(reason: "本单元尚未接入 URL 后处理") }
        let projection = string("projection")
        if operation != "AnalyzeRule.getElements" && projection != nil { throw Skip(reason: "该入口尚未实现投影 \(projection!)") }
        switch operation {
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
        case "AnalyzeByJSoup.getStringList":
            let value = try UnsupportedSelectorEngine(mode: .default).evaluate(input.rule, content: input.document ?? NSNull(), operation: .stringList, context: parser)
            guard let list = value as? [String] else { throw Skip(reason: "schema 尚无该结果类型") }
            return .stringList(list)
        default: throw Skip(reason: "尚未实现规则 operation=\(operation)")
        }
    }

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
            let rule = input.rule
            if rule.lowercased().contains("<js>") || rule.lowercased().contains("@js:") || (rule.contains("{{") && rule.contains("}}")) {
                throw Skip(reason: "依赖 JavaScript 求值；本单元不执行 <js>/@js:/{{}}")
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
