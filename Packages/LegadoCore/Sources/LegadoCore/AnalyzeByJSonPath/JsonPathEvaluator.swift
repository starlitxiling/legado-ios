import Foundation

enum JsonPathEvaluator {
    static func read(_ steps: [JsonPathStep], root: Any, document: Any? = nil) throws -> Any {
        var nodes: [Any] = [root]
        var indefinite = false
        for (index, step) in steps.enumerated() {
            let isLeaf = index == steps.count - 1
            indefinite = indefinite || step.indefinite(isLeaf: isLeaf)
            var next: [Any] = []
            for node in nodes {
                do { next += try apply(step, node: node, root: document ?? root, isLeaf: isLeaf) }
                catch JsonPathError.pathNotFound {
                    if !indefinite { throw JsonPathError.pathNotFound }
                }
            }
            nodes = next
        }
        if indefinite { return nodes }
        guard let node = nodes.first else { throw JsonPathError.pathNotFound }
        return node
    }

    private static func children(_ node: Any) -> [Any] {
        if let list = node as? [Any] { return list }
        if let object = node as? JsonPathObject { return object.orderedKeys.compactMap { object.object(forKey: $0) } }
        if let object = node as? NSDictionary { return object.allKeys.compactMap { object.object(forKey: $0) } }
        return []
    }

    private static func apply(_ step: JsonPathStep, node: Any, root: Any, isLeaf: Bool) throws -> [Any] {
        switch step {
        case .property(let keys):
            guard let object = node as? [String: Any] else { throw JsonPathError.pathNotFound }
            if keys.count == 1 {
                guard let value = object[keys[0]] else { throw JsonPathError.pathNotFound }
                return [value]
            }
            if !isLeaf { return keys.compactMap { object[$0] } }
            return [JsonPathObject(keys.compactMap { key in object[key].map { (key, $0) } })]
        case .wildcard: return children(node)
        case .indices(let indices):
            guard let list = node as? [Any] else { throw JsonPathError.pathNotFound }
            var result: [Any] = []
            for index in indices {
                let index = index < 0 ? list.count + index : index
                if list.indices.contains(index) { result.append(list[index]) }
                else if indices.count == 1 { throw JsonPathError.pathNotFound }
            }
            return result
        case .slice(let start, let end, let step):
            guard let list = node as? [Any] else { throw JsonPathError.pathNotFound }
            func bound(_ value: Int?, fallback: Int, lower: Int, upper: Int) -> Int {
                guard let value else { return fallback }
                return min(upper, max(lower, value < 0 ? list.count + value : value))
            }
            let lower = step > 0 ? 0 : -1, upper = step > 0 ? list.count : list.count - 1
            let first = bound(start, fallback: step > 0 ? 0 : list.count - 1, lower: lower, upper: upper)
            let last = bound(end, fallback: step > 0 ? list.count : -1, lower: lower, upper: upper)
            var result: [Any] = [], index = first
            while step > 0 ? index < last : index > last {
                if list.indices.contains(index) { result.append(list[index]) }
                let (next, overflow) = index.addingReportingOverflow(step)
                if overflow { break }
                index = next
            }
            return result
        case .recursive(let box):
            guard node is NSDictionary || node is [Any] else { return [] }
            var result: [Any] = []
            if case .filter(let predicate) = box.step {
                if !(node is [Any]), predicate.matches(node, root: root) { result.append(node) }
            } else {
                do { result += try apply(box.step, node: node, root: root, isLeaf: isLeaf) }
                catch JsonPathError.pathNotFound { }
            }
            for child in children(node) { result += try apply(step, node: child, root: root, isLeaf: isLeaf) }
            return result
        case .filter(let predicate):
            let candidates = (node as? [Any]) ?? (node is [String: Any] ? [node] : [])
            return candidates.filter { predicate.matches($0, root: root) }
        case .function(let name, let arguments):
            let values = arguments.map { $0.value(node, root: root) ?? NSNull() }
            let parameters = values.flatMap { ($0 as? [Any]) ?? [$0] }
            switch name {
            case "length", "size":
                let target = values.first ?? node
                if let list = target as? [Any] { return [list.count] }
                if let object = target as? [String: Any] { return [object.count] }
                return [NSNull()]
            case "keys":
                if let object = node as? JsonPathObject { return [object.orderedKeys] }
                guard let object = node as? NSDictionary else { throw JsonPathError.invalidFunction(name) }
                return [object.allKeys]
            case "concat":
                return [((node as? [Any] ?? []).compactMap { $0 as? String } + parameters.compactMap { $0 as? String }).joined()]
            case "append":
                guard let list = node as? [Any] else { return [node] }
                return [list + values]
            case "first", "last", "index":
                guard let list = node as? [Any], !list.isEmpty else { throw JsonPathError.invalidFunction(name) }
                let index: Int
                if name == "first" { index = 0 }
                else if name == "last" { index = list.count - 1 }
                else {
                    guard let raw = parameters.compactMap({ JsonPathPredicate.number($0) }).first,
                          raw.isFinite, raw > Double(Int.min), raw < Double(Int.max) else { throw JsonPathError.invalidFunction(name) }
                    let requested = Int(raw)
                    index = requested < 0 ? list.count + requested : requested
                    if requested < 0 && index <= 0 { throw JsonPathError.invalidFunction(name) }
                }
                guard list.indices.contains(index) else { throw JsonPathError.invalidFunction(name) }
                return [list[index]]
            case "min", "max", "sum", "avg", "stddev":
                let numbers = ((node as? [Any] ?? []) + parameters).compactMap { JsonPathPredicate.number($0) }
                guard !numbers.isEmpty else { throw JsonPathError.invalidFunction(name) }
                let sum = numbers.reduce(0, +), count = Double(numbers.count)
                switch name {
                case "min": return [numbers.min()!]
                case "max": return [numbers.max()!]
                case "avg": return [sum / count]
                case "stddev": return [sqrt(numbers.reduce(0) { $0 + $1 * $1 } / count - sum * sum / count / count)]
                default: return [sum]
                }
            default: throw JsonPathError.invalidFunction(name)
            }
        }
    }
}
