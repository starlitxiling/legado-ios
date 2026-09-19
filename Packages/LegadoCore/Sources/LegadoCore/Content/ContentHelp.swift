import Foundation

public enum ContentHelpError: Error, Equatable {
    case invalidParagraphRange(Int, Int, Int)
}

public enum ContentHelp {
    private static let end = "？。！?!~"
    private static let endP = ".？。！?!~"
    private static let mid = ".，、,—…"
    private static let say = "问说喊唱叫骂道着答"
    private static let before = "，：,:"
    private static let quote = "\"“”"
    private static let right = "\"”"

    public static func reSegment(_ content: String, chapterName: String,
                                 random: () -> Double = { Double.random(in: 0..<1) }) throws -> String {
        try Task.checkCancellation()
        let dict = try dictionary(content)
        var value = try replace(content, #"&quot;"#, "“")
        value = try replace(value, #"[:：]['"‘”“]+"#, "：“")
        value = try replace(value, #"["”“]+\s*["”“][\s"”“]*"#, "”\n“")
        let lines = try split(value, #"\n(\s*)"#)
        var buffer = "  "
        if trimASCII(chapterName) != trimASCII(lines[0]) {
            buffer += try replace(lines[0], #"[\u3000\s]+"#, "")
        }
        for line in lines.dropFirst() {
            let units = Array(buffer.utf16)
            if let last = units.last, match(end, last) || (match(right, last) && units.count > 1 && match(end, units[units.count - 2])) {
                buffer += "\n"
            }
            buffer += try replace(line, #"[\u3000\s]"#, "")
        }
        value = try replace(buffer, #"["”“]+\s*["”“]+"#, "”\n“")
        value = try replace(value, #"["”“]+(？。！?!~)["”“]+"#, "”$1\n“")
        value = try replace(value, #"["”“]+(？。！?!~)([^"”“])"#, "”$1\n$2")
        value = try replace(value, #"([问说喊唱叫骂道着答])[\.。]"#, "$1。\n")
        buffer = ""
        for line in try split(value, "\n") {
            try Task.checkCancellation()
            buffer += "\n" + (try findNewLines(line, dict: dict, random: random))
        }
        value = try reduceLength(buffer)
        value = try replace(value, #"^\s+"#, "")
        value = try replace(value, #"\s*["”“]+\s*["”“][\s"”“]*"#, "”\n“")
        value = try replace(value, #"[:：][”“"\s]+"#, "：“")
        value = try replace(value, #"\n["“”]([^\n"“”]+)([,:，：]["”“])([^\n"“”]+)"#, "\n$1：“$3")
        return try replace(value, #"\n(\s*)"#, "\n")
    }

    private static func reduceLength(_ text: String) throws -> String {
        var lines = try split(text, "\n")
        let regex = try expression(#"^["”“][^"”“]+["”“]$"#)
        let dialogueLines = lines.map { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        var dialogue = 0
        for index in lines.indices {
            if dialogueLines[index] {
                if dialogue < 0 { dialogue = 1 } else if dialogue < 2 { dialogue += 1 }
            } else if dialogue > 1 {
                lines[index] = splitQuote(lines[index]); dialogue -= 1
            } else if dialogue > 0 && index < lines.count - 2 && dialogueLines[index + 1] {
                lines[index] = splitQuote(lines[index])
            }
        }
        return lines.map { "\n" + $0 }.joined()
    }

    private static func splitQuote(_ text: String) -> String {
        let units = Array(text.utf16), count = text.utf16.count
        guard count >= 3 else { return text }
        if match(quote, units[0]) {
            let index = seekIndex(units, quote, from: 1, to: count - 2, forward: true) + 1
            if index > 1 && !match(before, units[index - 1]) {
                return string(units[0..<index]) + "\n" + string(units[index..<count])
            }
        } else if match(quote, units[count - 1]) {
            let index = count - 1 - seekIndex(units, quote, from: 1, to: count - 2, forward: false)
            if index > 1 && !match(before, units[index - 1]) {
                return string(units[0..<index]) + "\n" + string(units[index..<count])
            }
        }
        return text
    }

    private static func forceSplit(_ units: [UInt16], offset: Int, minimum: Int,
                                   gain: Int, trigger: Int, random: () -> Double) -> [Int] {
        let ends = seekIndexes(units, endP, from: 0, to: units.count - 2)
        let mids = seekIndexes(units, mid, from: 0, to: units.count - 2)
        if ends.count < trigger && mids.count < trigger * 3 { return [] }
        var result: [Int] = [], j = 0, i = minimum
        while i < ends.count {
            var k = 0
            while j < mids.count {
                if mids[j] < ends[i] { k += 1 }
                j += 1
            }
            if random() * Double(gain) < 0.8 + Double(k) / 2.5 {
                result.append(ends[i] + offset)
                i = max(i + minimum, i)
            }
            i += 1
        }
        return result
    }

    private static func findNewLines(_ text: String, dict: Set<String>, random: () -> Double) throws -> String {
        let original = Array(text.utf16)
        var units = original, quotes: [Int] = [], breaks: [Int] = []
        var modes = Array(repeating: 0, count: units.count), waiting = false
        for i in original.indices where match(quote, original[i]) {
            let size = quotes.count
            if size > 0 && i - quotes[size - 1] == 2 {
                if match(waiting ? ",，、/" : ",，、/和与或", original[i - 1]) {
                    units[i] = 0x201C; units[i - 2] = 0x201D
                    quotes.removeLast(); modes[size - 1] = 1; modes[size] = -1
                    continue
                }
            }
            quotes.append(i)
            if i > 1 {
                let previous = original[i - 1]
                var previousBefore: UInt16 = 0
                if match(before, previous) {
                    if quotes.count > 1 {
                        let last = quotes[quotes.count - 2]
                        var p = 0
                        if match(",，", previous) && quotes.count > 2 {
                            p = quotes[quotes.count - 3]
                            if p > 0 { previousBefore = original[p - 1] }
                        }
                        if match(endP, previousBefore) { breaks.append(p - 1) }
                        else if !match("的", previousBefore) {
                            let lastEnd = seekLast(original, end, from: i, to: last)
                            breaks.append(lastEnd > 0 ? lastEnd : last)
                        }
                    }
                    waiting = true; modes[size] = 1
                    if size > 0 { modes[size - 1] = -1 }
                    if size > 1 { modes[size - 2] = 1 }
                } else if waiting { waiting = false; breaks.append(i) }
            }
        }
        let size = quotes.count
        var opened = false
        if size > 0 {
            for i in 0..<size {
                if modes[i] > 0 { opened = true }
                else if modes[i] < 0 {
                    if !opened && i > 0 { modes[i] = 3 }
                    opened = false
                } else { opened.toggle(); modes[i] = opened ? 2 : -2 }
            }
            if opened {
                if quotes[size - 1] - units.count > -3 {
                    if size > 1 { modes[size - 2] = 4 }
                    modes[size - 1] = -4
                } else if units.count > 1 && !match(say, units[units.count - 2]) { units.append(0x201D) }
            }
            var previous = -1
            let start = quotes[0] > 0 ? 0 : 1
            if start == 1 { previous = 0 }
            for i in start..<size {
                let j = quotes[i] - 1
                if previous < 0 && modes[i] > 0 && match(end, units[j]) { breaks.append(j) }
                previous = modes[i]
            }
        }
        breaks = breaks.filter { i in
            if match("\"'”“", units[i]) {
                let start = seekLast(original, "\"'”“", from: i - 1, to: i - 16)
                if start > 0 && (dict.contains(string(original[(start + 1)..<i])) || match("的地得", original[start])) {
                    return false
                }
            }
            return true
        }
        breaks = Array(Set(breaks)).sorted()
        var j = 0, progress = 0, nextLine = breaks.first ?? -1
        var gain = 3, minimum = 0, trigger = 2
        for q in quotes {
            gain = q > 0 ? 4 : 3; minimum = q > 0 ? 2 : 0; trigger = q > 0 ? 4 : 2
            while j < breaks.count {
                if nextLine >= q { break }
                nextLine = breaks[j]
                if progress < nextLine {
                    breaks += forceSplit(Array(units[progress..<nextLine]), offset: progress,
                        minimum: minimum, gain: gain, trigger: trigger, random: random)
                    progress = nextLine + 1
                }
                j += 1
            }
            if progress < q {
                breaks += forceSplit(Array(units[progress...q]), offset: progress,
                    minimum: minimum, gain: gain, trigger: trigger, random: random)
                progress = q + 1
            }
        }
        while j < breaks.count {
            nextLine = breaks[j]
            if progress < nextLine {
                breaks += forceSplit(Array(units[progress..<nextLine]), offset: progress,
                    minimum: minimum, gain: gain, trigger: trigger, random: random)
                progress = nextLine + 1
            }
            j += 1
        }
        if progress < units.count {
            breaks += forceSplit(Array(units[progress..<units.count]), offset: progress,
                minimum: minimum, gain: gain, trigger: trigger, random: random)
        }
        var insertQuotes = Array(repeating: false, count: size)
        opened = false
        for i in 0..<size {
            let p = quotes[i]
            if modes[i] > 0 {
                units[p] = 0x201C; insertQuotes[i] = opened; opened = true
            } else if modes[i] < 0 { units[p] = 0x201D; opened = false }
            else { opened.toggle(); units[p] = opened ? 0x201C : 0x201D }
        }
        breaks = Array(Set(breaks)).sorted()
        var output: [UInt16] = []
        j = 0; progress = 0; nextLine = breaks.first ?? -1
        for i in quotes.indices {
            let q = quotes[i]
            while j < breaks.count {
                if nextLine >= q { break }
                nextLine = breaks[j]
                guard progress <= nextLine + 1 else {
                    throw ContentHelpError.invalidParagraphRange(progress, nextLine + 1, units.count)
                }
                output += units[progress..<(nextLine + 1)]; output.append(10)
                progress = nextLine + 1; j += 1
            }
            if progress < q { output += units[progress...q]; progress = q + 1 }
            if insertQuotes[i] && output.count > 2 {
                if output.last == 10 { output.append(0x201C) }
                else { output.insert(contentsOf: [0x201D, 10], at: output.count - 1) }
            }
        }
        while j < breaks.count {
            nextLine = breaks[j]
            if progress <= nextLine { output += units[progress..<(nextLine + 1)]; output.append(10); progress = nextLine + 1 }
            j += 1
        }
        if progress < units.count { output += units[progress..<units.count] }
        return string(output[...])
    }

    private static func dictionary(_ text: String) throws -> Set<String> {
        let regex = try expression(#"(?<=["'”“])([^\n\p{P}]{1,16})(?=["'”“])"#)
        let input = text as NSString
        var seen = Set<String>(), repeated = Set<String>()
        for match in regex.matches(in: text, range: NSRange(location: 0, length: input.length)) {
            let word = input.substring(with: match.range)
            if !seen.insert(word).inserted { repeated.insert(word) }
        }
        return repeated
    }

    private static func seekIndexes(_ units: [UInt16], _ key: String, from: Int, to: Int) -> [Int] {
        let limit = to > 0 ? min(units.count, to) : units.count
        guard max(0, from) < limit else { return [] }
        var result: [Int] = []
        for i in max(0, from)..<limit where match(key, units[i]) {
            if let last = result.last, i - last == 1 { result[result.count - 1] = i }
            else { result.append(i) }
        }
        return result
    }

    private static func seekLast(_ units: [UInt16], _ key: String, from: Int, to: Int) -> Int {
        guard units.count - from >= 1 else { return -1 }
        var i = min(units.count - 1, from)
        while i > max(0, to) {
            if match(key, units[i]) { return i }
            i -= 1
        }
        return -1
    }

    private static func seekIndex(_ units: [UInt16], _ key: String, from: Int, to: Int, forward: Bool) -> Int {
        let limit = to > 0 ? min(units.count, to) : units.count
        guard max(0, from) < limit else { return -1 }
        for i in max(0, from)..<limit where match(key, units[forward ? i : units.count - i - 1]) { return i }
        return -1
    }

    private static func match(_ key: String, _ value: UInt16) -> Bool { key.utf16.contains(value) }
    private static func string(_ units: ArraySlice<UInt16>) -> String { String(decoding: units, as: UTF16.self) }
    private static func trimASCII(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}"..."\u{20}"))
    }
    private static func expression(_ pattern: String) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: pattern.replacingOccurrences(of: #"\s"#, with: #"[ \t\n\x{0B}\f\r]"#))
    }
    private static func replace(_ text: String, _ pattern: String, _ replacement: String) throws -> String {
        try expression(pattern).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
    private static func split(_ text: String, _ pattern: String) throws -> [String] {
        let input = text as NSString
        var result: [String] = [], start = 0
        for match in try expression(pattern).matches(in: text, range: NSRange(location: 0, length: input.length)) {
            result.append(input.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = NSMaxRange(match.range)
        }
        result.append(input.substring(from: start))
        return result
    }
}
