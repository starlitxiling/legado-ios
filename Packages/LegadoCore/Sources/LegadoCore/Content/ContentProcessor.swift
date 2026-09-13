import Foundation

public enum ContentProcessorError: Error, Equatable {
    case invalidRule(Int64)
    case regexTimeout(Int64)
}

public struct ContentProcessor {
    public struct Result {
        public let sameTitleRemoved: Bool
        public let paragraphs: [String]
        public let effectiveRuleIDs: [Int64]
        public var text: String { paragraphs.joined(separator: "\n") }
    }

    public let rules: [ReplaceRule]
    private let clock: () -> TimeInterval
    private let paragraphIndent: String
    private let onError: (ReplaceRule, Error) -> Void
    private let disableRule: (Int64) -> Void
    private final class DisabledRules {
        private let lock = NSLock()
        private var ids = Set<Int64>()
        func contains(_ id: Int64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return ids.contains(id)
        }
        func insert(_ id: Int64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return ids.insert(id).inserted
        }
    }
    private let disabled = DisabledRules()
    public init(rules: [ReplaceRule] = [], clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                paragraphIndent: String = "　　", onError: @escaping (ReplaceRule, Error) -> Void = { _, _ in },
                disableRule: @escaping (Int64) -> Void = { _ in }) {
        self.rules = rules.enumerated().sorted { a, b in
            a.element.order == b.element.order ? a.offset < b.offset : a.element.order < b.element.order
        }.map(\.element)
        self.clock = clock
        self.paragraphIndent = paragraphIndent; self.onError = onError; self.disableRule = disableRule
    }

    public func title(book: Book, chapter: BookChapter, useReplace: Bool = true) throws -> String {
        try Task.checkCancellation()
        var title = (chapter.title ?? "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        if useReplace && book.readConfig?.useReplaceRule != false {
            for rule in rules where rule.scopeTitle && applies(rule, book: book) {
                do {
                    let changed = try apply(rule, to: title, chapter: chapter, book: book)
                    if !changed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = changed }
                } catch { try handle(error, rule: rule) }
            }
        }
        return title
    }

    public func getContent(book: Book, chapter: BookChapter, content: String, includeTitle: Bool = true,
                           useReplace: Bool = true, removeDuplicateParagraphs: Bool = false) throws -> Result {
        try Task.checkCancellation()
        var text = content
        var removed = false
        var effective: [Int64] = []
        if content != "null" {
            var candidates = [chapter.title ?? ""]
            var candidateIndex = 0
            while candidateIndex < candidates.count {
                let candidate = candidates[candidateIndex]
                candidateIndex += 1
                if candidate.isEmpty { break }
                let pattern = "^(?:\\s|\\p{P}|" + NSRegularExpression.escapedPattern(for: book.name ?? "") + ")*"
                    + NSRegularExpression.escapedPattern(for: candidate)
                    + "[\\t\\x{0B}\\f\\p{Zs}]*(?:(?:\\r\\n|\\r|\\n)\\s*|$)"
                let regex = try NSRegularExpression(pattern: pattern)
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    text = (text as NSString).substring(from: NSMaxRange(match.range)); removed = true; break
                }
                if candidates.count == 1 && useReplace && book.readConfig?.useReplaceRule != false {
                    candidates.append(try title(book: book, chapter: chapter, useReplace: useReplace))
                }
            }
            // 繁简转换与 ContentHelp.reSegment 在阅读排版单元接入。
            if useReplace && book.readConfig?.useReplaceRule != false {
                text = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                for rule in rules where rule.scopeContent && applies(rule, book: book) {
                    do {
                        let changed = try apply(rule, to: text, chapter: chapter, book: book)
                        if changed != text { effective.append(rule.id); text = changed }
                    } catch {
                        try handle(error, rule: rule)
                        if case ContentProcessorError.regexTimeout = error {
                            text = (rule.name ?? "") + String(describing: error)
                        }
                    }
                }
            }
        }
        let title = includeTitle ? try title(book: book, chapter: chapter, useReplace: useReplace) : ""
        let combined = includeTitle ? title + "\n" + text : text
        var seen = Set<String>(), paragraphs: [String] = []
        for line in combined.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !removeDuplicateParagraphs || seen.insert(value).inserted else { continue }
            paragraphs.append(paragraphs.isEmpty && includeTitle ? value : paragraphIndent + value)
        }
        try Task.checkCancellation()
        return Result(sameTitleRemoved: removed, paragraphs: paragraphs, effectiveRuleIDs: effective)
    }

    private func handle(_ error: Error, rule: ReplaceRule) throws {
        try Task.checkCancellation()
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
        onError(rule, error)
        if case ContentProcessorError.regexTimeout = error, disabled.insert(rule.id) { disableRule(rule.id) }
    }

    private func applies(_ rule: ReplaceRule, book: Book) -> Bool {
        guard rule.isEnabled && !disabled.contains(rule.id) else { return false }
        let name = book.name ?? "", origin = book.origin ?? ""
        if let excluded = rule.excludeScope, Self.like(excluded, containsPattern: name) || Self.like(excluded, containsPattern: origin) { return false }
        guard let scope = rule.scope, !scope.isEmpty else { return true }
        return Self.like(scope, containsPattern: name) || Self.like(scope, containsPattern: origin)
    }

    private static func like(_ value: String, containsPattern: String) -> Bool {
        func fold(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.prefix(while: { $0.value != 0 }).map {
                (65...90).contains($0.value) ? UnicodeScalar($0.value + 32)! : $0
            }))
        }
        // DAO 没有 ESCAPE 子句；反斜杠是普通字符，通配符来自书名或书源参数。
        let pattern = fold("%" + containsPattern + "%").unicodeScalars.map { scalar in
            scalar == "%" ? "[\\s\\S]*" : scalar == "_" ? "[\\s\\S]" : NSRegularExpression.escapedPattern(for: String(scalar))
        }.joined()
        let input = fold(value)
        return input.range(of: "\\A" + pattern + "\\z", options: .regularExpression) != nil
    }

    public func apply(_ rule: ReplaceRule, to text: String, chapter: BookChapter? = nil, book: Book? = nil) throws -> String {
        try Task.checkCancellation()
        guard let pattern = rule.pattern, !pattern.isEmpty else { return text }
        let replacement = rule.replacement ?? ""
        if !rule.isRegex { return text.replacingOccurrences(of: pattern, with: replacement) }
        guard !(pattern.hasSuffix("|") && !pattern.hasSuffix("\\|")),
              let regex = try? NSRegularExpression(pattern: pattern) else { throw ContentProcessorError.invalidRule(rule.id) }
        let milliseconds = rule.timeoutMillisecond > 0 ? rule.timeoutMillisecond : 3000
        let deadline = clock() + Double(milliseconds) / 1000
        let input = text as NSString
        var output = "", position = 0
        var failure: Error?
        regex.enumerateMatches(in: text, options: [.reportProgress, .reportCompletion],
                               range: NSRange(location: 0, length: input.length)) { match, _, stop in
            if Task.isCancelled { failure = CancellationError(); stop.pointee = true; return }
            if clock() >= deadline { failure = ContentProcessorError.regexTimeout(rule.id); stop.pointee = true; return }
            guard let match else { return }
            output += input.substring(with: NSRange(location: position, length: match.range.location - position))
            do {
                let template: String
                if replacement.hasPrefix("@js:") {
                    let engine = JsEngine(httpClient: ReplayHttpClient())
                    let bindings: [String: Any] = ["result": input.substring(with: match.range),
                        "chapter": try chapter.map(WebBookContext.object) as Any? ?? NSNull(),
                        "book": try book.map(WebBookContext.object) as Any? ?? NSNull()]
                    let value = ruleText(try engine.evaluateScript(String(replacement.dropFirst(4)), bindings: bindings))
                    template = value.replacingOccurrences(of: "\\", with: "\\\\")
                } else { template = replacement }
                if clock() >= deadline { throw ContentProcessorError.regexTimeout(rule.id) }
                output += try expand(template, match: match, input: input, regex: regex)
            }
            catch { failure = error; stop.pointee = true; return }
            position = NSMaxRange(match.range)
        }
        if let failure { throw failure }
        return output + input.substring(from: position)
    }

    private func expand(_ template: String, match: NSTextCheckingResult, input: NSString,
                        regex: NSRegularExpression) throws -> String {
        let chars = Array(template)
        var cursor = 0, output = ""
        func digit(_ value: Character) -> Int? {
            value >= "0" && value <= "9" ? Int(String(value)) : nil
        }
        while cursor < chars.count {
            let char = chars[cursor]; cursor += 1
            if char == "\\" {
                guard cursor < chars.count else { throw RuleEvaluationError.invalidReplacement }
                output.append(chars[cursor]); cursor += 1
            } else if char == "$" {
                guard cursor < chars.count else { throw RuleEvaluationError.invalidReplacement }
                let range: NSRange
                if chars[cursor] == "{" {
                    cursor += 1
                    let start = cursor
                    while cursor < chars.count && chars[cursor] != "}" { cursor += 1 }
                    guard cursor < chars.count && cursor > start else { throw RuleEvaluationError.invalidReplacement }
                    let name = String(chars[start..<cursor]); cursor += 1
                    guard name.first?.isLetter == true && name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
                        throw RuleEvaluationError.invalidReplacement
                    }
                    _ = try NSRegularExpression(pattern: "(?:" + regex.pattern + ")|\\k<" + name + ">")
                    range = match.range(withName: name)
                } else {
                    guard var group = digit(chars[cursor]), group < match.numberOfRanges else { throw RuleEvaluationError.invalidReplacement }
                    cursor += 1
                    while cursor < chars.count, let next = digit(chars[cursor]), group * 10 + next < match.numberOfRanges {
                        group = group * 10 + next; cursor += 1
                    }
                    range = match.range(at: group)
                }
                if range.location != NSNotFound { output += input.substring(with: range) }
            } else { output.append(char) }
        }
        return output
    }
}
