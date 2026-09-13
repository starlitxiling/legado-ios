import Foundation

public enum SourceExporter {
    public static func bookSources(_ sources: [BookSource]) throws -> String {
        try render(sources, depth: 0)
    }

    public static func replaceRules(_ rules: [ReplaceRule]) throws -> String {
        try render(rules, depth: 0)
    }

    public static func bookSource(_ source: BookSource) throws -> String {
        try render(source, depth: 0)
    }

    // Gson 按实体声明顺序写字段，且不调用 serializeNulls；JSONEncoder 不保证键顺序。
    private static func render(_ value: Any, depth: Int) throws -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            guard let wrapped = mirror.children.first else { return "null" }
            return try render(wrapped.value, depth: depth)
        }
        let indent = String(repeating: "  ", count: depth)
        if mirror.displayStyle == .collection {
            let items = try mirror.children.map { try render($0.value, depth: depth + 1) }
            return items.isEmpty ? "[]" : "[\n" + items.map { indent + "  " + $0 }.joined(separator: ",\n") + "\n" + indent + "]"
        }
        if mirror.displayStyle == .struct {
            let items = try mirror.children.compactMap { child -> String? in
                guard let key = child.label else { return nil }
                let optional = Mirror(reflecting: child.value)
                if optional.displayStyle == .optional && optional.children.isEmpty { return nil }
                return try render(key, depth: 0) + ": " + render(child.value, depth: depth + 1)
            }
            return items.isEmpty ? "{}" : "{\n" + items.map { indent + "  " + $0 }.joined(separator: ",\n") + "\n" + indent + "}"
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
