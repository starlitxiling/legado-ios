/// 有状态规则切分器。对应规则引擎规格 §3；位置和分隔符长度使用 Kotlin 的 UTF-16 码元偏移。
public final class RuleAnalyzer {
    public enum AnalysisError: Error, Equatable {
        case exhausted
        case invalidDelimiter
        case unbalanced(position: Int)
    }

    public private(set) var position = 0
    public private(set) var step = 0
    public private(set) var elementsType = ""
    private let queue: [UInt16]
    private let code: Bool
    private var start = 0
    private var startX = 0

    /// 创建独立游标；`code` 选择 §3.1 的代码平衡组。
    public init(_ rule: String, code: Bool = false) {
        queue = Array(rule.utf16)
        self.code = code
    }

    /// §3.1：跳过前导 @ 和 ASCII 空白、控制字符；耗尽时抛错。
    public func trim() throws {
        guard position < queue.count else { throw AnalysisError.exhausted }
        guard Unicode.Scalar(queue[position]) == "@" || queue[position] < 33 else { return }
        while position < queue.count, Unicode.Scalar(queue[position]) == "@" || queue[position] < 33 {
            position += 1
        }
        guard position < queue.count else { throw AnalysisError.exhausted }
        start = position
        startX = position
    }

    /// §3.1：区分大小写搜索，未命中时保留游标。
    @discardableResult
    public func consumeTo(_ sequence: String) -> Bool {
        start = position
        let token = Array(sequence.utf16)
        guard let found = find(token, from: position) else { return false }
        position = found
        return true
    }

    /// §3.1；Kotlin :49-65：最早位置优先，同位置按参数顺序，未命中时保留游标。
    @discardableResult
    public func consumeToAny(_ sequences: [String]) -> Bool {
        var cursor = position
        let tokens = sequences.map { Array($0.utf16) }
        while cursor < queue.count {
            for token in tokens where !token.isEmpty && matches(token, at: cursor) {
                step = token.count
                position = cursor
                return true
            }
            cursor += 1
        }
        return false
    }

    /// §3.1：查找指定括号字符，不移动游标；未找到返回 -1。
    public func findToAny(_ characters: [Unicode.Scalar]) -> Int {
        guard position < queue.count else { return -1 }
        return (position..<queue.count).first { offset in
            characters.contains { $0.value == UInt32(queue[offset]) }
        } ?? -1
    }

    /// §3.1：引号内没有转义；引号外反斜杠跳过下一个字符。
    @discardableResult
    public func chompRuleBalanced(open: Unicode.Scalar, close: Unicode.Scalar) -> Bool {
        chompBalanced(open: open, close: close, isCode: false)
    }

    /// §3.1：所有位置识别转义，方括号为主深度。
    @discardableResult
    public func chompCodeBalanced(open: Unicode.Scalar, close: Unicode.Scalar) -> Bool {
        chompBalanced(open: open, close: close, isCode: true)
    }

    /// §3.2：保留空项，只采用第一个组外分隔符类型；无分隔符不校验括号。
    /// Kotlin :185,194：顶层引号和反斜杠均作为普通字符。
    public func splitRule(separators: [String]) throws -> [String] {
        guard !separators.isEmpty, separators.allSatisfy({ !$0.isEmpty }) else {
            throw AnalysisError.invalidDelimiter
        }
        elementsType = separators.count == 1 ? separators[0] : ""
        var active = separators.map { Array($0.utf16) }
        var result: [String] = []
        var segment = startX
        var nextSeparator = findSeparator(active)
        while position < queue.count {
            // §3.2 在不存在后续分隔符时直接返回尾段。
            if let next = nextSeparator, next < position {
                nextSeparator = findSeparator(active)
            }
            guard nextSeparator != nil else { break }
            if let character = Unicode.Scalar(queue[position]), character == "[" || character == "(" {
                let opening = position
                let closing: Unicode.Scalar = character == "[" ? "]" : ")"
                guard chompBalanced(open: character, close: closing, isCode: code) else {
                    throw AnalysisError.unbalanced(position: opening)
                }
                continue
            }
            if let token = active.first(where: { matches($0, at: position) }) {
                result.append(text(segment, position))
                step = token.count
                elementsType = String(decoding: token, as: UTF16.self)
                active = [token]
                position += step
                segment = position
            } else {
                position += 1
            }
        }
        result.append(text(segment, queue.count))
        return result
    }

    /// §3.3；Kotlin :318-326：未闭合则跳过标记，空回调从组尾再跳过标记长度。
    /// 使用实例起点拼接；Kotlin :329 的返回判据是 startX 是否为零。
    public func innerRule(start marker: String, transform: (String) throws -> String) throws -> String {
        let token = Array(marker.utf16)
        guard let opening = token.first, Unicode.Scalar(opening) == "{" else { throw AnalysisError.invalidDelimiter }
        var result = ""
        while consumeTo(marker) {
            let found = position
            guard chompCodeBalanced(open: "{", close: "}") else {
                position = found + token.count
                continue
            }
            let replacement = try transform(text(found + 1, position - 1))
            if replacement.isEmpty {
                position += token.count
            } else {
                result += text(startX, found) + replacement
                startX = position
            }
        }
        return startX == 0 ? "" : result + text(startX, queue.count)
    }

    /// §3.3；Kotlin :346-364：命中开标记立即推进游标，拼接和返回使用实例起点。
    public func innerRule(start: String, end: String, transform: (String) throws -> String) throws -> String {
        let opening = Array(start.utf16)
        let closing = Array(end.utf16)
        guard !opening.isEmpty, !closing.isEmpty else { throw AnalysisError.invalidDelimiter }
        var result = ""
        while consumeTo(start) {
            let found = position
            position += opening.count
            let contentStart = position
            if consumeTo(end) {
                let replacement = try transform(text(contentStart, position))
                result += text(startX, found) + replacement
                position += closing.count
                startX = position
            }
        }
        return startX == 0 ? text(0, queue.count) : result + text(startX, queue.count)
    }

    private func chompBalanced(open: Unicode.Scalar, close: Unicode.Scalar, isCode: Bool) -> Bool {
        guard position < queue.count, UInt32(queue[position]) == open.value else { return false }
        let originalPosition = position
        var balanced = false
        defer {
            if !balanced { position = originalPosition }
        }
        var depth = 0
        var squareDepth = 0
        var quote: Unicode.Scalar?
        while position < queue.count {
            let character = Unicode.Scalar(queue[position])
            position += 1
            if character == "\\" && (isCode || quote == nil) {
                position = min(position + 1, queue.count)
                continue
            }
            if let current = quote {
                if character == current { quote = nil }
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                continue
            }
            if isCode && character == "[" {
                squareDepth += 1
            } else if isCode && character == "]" {
                squareDepth -= 1
            } else if !isCode || squareDepth == 0 {
                if character == open { depth += 1 }
                if character == close { depth -= 1 }
            }
            if depth == 0 && squareDepth == 0 {
                balanced = true
                return true
            }
        }
        return false
    }

    /// Kotlin :57,173：候选命中即记录长度，搜索失败保留上次长度。
    private func findSeparator(_ tokens: [[UInt16]]) -> Int? {
        var candidate: Int?
        for token in tokens {
            if let found = find(token, from: position), candidate == nil || found < candidate! {
                candidate = found
                step = token.count
            }
        }
        return candidate
    }

    private func matches(_ token: [UInt16], at offset: Int) -> Bool {
        offset + token.count <= queue.count && queue[offset..<(offset + token.count)].elementsEqual(token)
    }

    private func find(_ token: [UInt16], from offset: Int) -> Int? {
        guard offset <= queue.count else { return nil }
        return (offset...queue.count).first { matches(token, at: $0) }
    }

    private func text(_ lower: Int, _ upper: Int) -> String {
        String(decoding: queue[lower..<upper], as: UTF16.self)
    }
}
