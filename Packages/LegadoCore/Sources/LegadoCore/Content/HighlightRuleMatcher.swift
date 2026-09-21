import Foundation

public enum HighlightRuleMatcher {
    public struct Match: Equatable {
        public let range: NSRange
        public let ruleID: Int64
        public let style: String
    }
    public struct Result {
        public let matches: [Match]
        public let completed: Bool
    }

    public static func applicable(_ rules: [HighlightRule], book: Book) -> [HighlightRule] {
        rules.filter { rule in
            guard rule.isEnabled else { return false }
            guard let scope = rule.scope, !scope.isEmpty else { return true }
            return [book.name, book.origin].compactMap { $0 }.contains { !$0.isEmpty && scope.contains($0) }
        }.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    public static func match(text: String, titleLength: Int, rules: [HighlightRule], book: Book,
                             maximumMatches: Int = 10_000,
                             clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                             shouldContinue: () -> Bool = { !Task.isCancelled }) -> Result {
        let input = text as NSString
        guard input.length > 0, maximumMatches > 0 else { return Result(matches: [], completed: true) }
        let titleEnd = min(input.length, max(0, titleLength))
        var matches: [Match] = []
        for rule in applicable(rules, book: book) {
            guard shouldContinue() else { return Result(matches: matches, completed: false) }
            guard !rule.pattern.isEmpty, rule.applyToTitle || rule.applyToBody else { continue }
            let segments: [NSRange]
            if rule.applyToTitle && rule.applyToBody { segments = [NSRange(location: 0, length: input.length)] }
            else if rule.applyToTitle { segments = [NSRange(location: 0, length: titleEnd)] }
            else { segments = [NSRange(location: titleEnd, length: input.length - titleEnd)] }
            let regex: NSRegularExpression?
            if rule.isRegex {
                guard let compiled = try? NSRegularExpression(pattern: rule.pattern) else { continue }
                regex = compiled
            } else { regex = nil }
            let deadline = clock() + Double(max(1, rule.timeoutMillisecond)) / 1000
            for segment in segments where segment.length > 0 {
                let slice = input.substring(with: segment)
                let range = NSRange(location: 0, length: (slice as NSString).length)
                var completed = true
                func append(_ found: NSRange) -> Bool {
                    guard matches.count < maximumMatches else { return false }
                    guard found.length > 0 else { return true }
                    matches.append(Match(range: NSRange(location: segment.location + found.location, length: found.length), ruleID: rule.id, style: rule.style))
                    return true
                }
                if let regex {
                    regex.enumerateMatches(in: slice, options: [.reportProgress, .reportCompletion], range: range) { found, _, stop in
                        if !shouldContinue() || clock() > deadline { completed = false; stop.pointee = true; return }
                        if let found, !append(found.range) { completed = false; stop.pointee = true }
                    }
                } else {
                    var start = 0
                    while start < range.length {
                        guard shouldContinue() else { completed = false; break }
                        let found = (slice as NSString).range(of: rule.pattern, options: .literal, range: NSRange(location: start, length: range.length - start))
                        if found.location == NSNotFound { break }
                        guard append(found) else { completed = false; break }
                        start = NSMaxRange(found)
                    }
                }
                if !completed { return Result(matches: matches, completed: false) }
            }
        }
        return Result(matches: matches, completed: true)
    }
}
