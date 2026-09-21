import Foundation

public struct HighlightStyle: Hashable {
    public struct Decoration: Hashable {
        public var color: Int64 = 0
    }
    public struct Underline: Hashable {
        public var kind = "SOLID"
        public var color: Int64 = 0
        public var width = 1.0
        public var distance = 0.0
    }
    public struct Shadow: Hashable {
        public var color: Int64 = 0x80000000
        public var radius = 3.0
        public var dx = 2.0
        public var dy = 2.0
    }
    public var fill: Int64 = 0
    public var fillShape = "RECTANGLE"
    public var textColor: Int64 = 0
    public var bold = false
    public var italic = false
    public var underline: Underline?
    public var strike: Decoration?
    public var box: Decoration?
    public var emphasis: Decoration?
    public var shadow: Shadow?
    public var fontPath = ""
    public var pillPaddingScale = 1.0
    public var fontSize: Double?
    public var letterSpacing: Double?

    public init(json: String = "") {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
        func number(_ key: String, _ values: [String: Any] = object, fallback: Double = 0) -> Double {
            let value = (values[key] as? NSNumber)?.doubleValue ?? (values[key] as? String).flatMap(Double.init) ?? fallback
            return value.isFinite ? value : fallback
        }
        fill = Int64(clamping: (object["fill"] as? NSNumber)?.int64Value ?? 0)
        textColor = (object["textColor"] as? NSNumber)?.int64Value ?? 0
        let shape = object["fillShape"] as? String ?? "RECTANGLE"
        fillShape = ["RECTANGLE", "ROUNDED", "MARKER", "HALF", "BASELINE", "PILL"].contains(shape) ? shape : "RECTANGLE"
        bold = object["bold"] as? Bool ?? false
        italic = object["italic"] as? Bool ?? false
        fontPath = object["fontPath"] as? String ?? ""
        pillPaddingScale = min(2, max(0.25, number("pillPaddingScale", fallback: 1)))
        if object["fontSize"] != nil, !(object["fontSize"] is NSNull) { fontSize = min(100, max(5, number("fontSize", fallback: 20))) }
        if object["letterSpacing"] != nil, !(object["letterSpacing"] is NSNull) { letterSpacing = min(1, max(-0.5, number("letterSpacing"))) }
        if let values = object["underline"] as? [String: Any] {
            let kind = values["kind"] as? String ?? "SOLID"
            underline = Underline(kind: ["SOLID", "WAVY", "DASHED", "DOTTED", "DOUBLE"].contains(kind) ? kind : "SOLID",
                color: (values["color"] as? NSNumber)?.int64Value ?? 0,
                width: min(10, max(0, number("width", values, fallback: 1))),
                distance: min(30, max(0, number("distance", values))))
        }
        func decoration(_ key: String) -> Decoration? {
            guard let values = object[key] as? [String: Any] else { return nil }
            return Decoration(color: (values["color"] as? NSNumber)?.int64Value ?? 0)
        }
        strike = decoration("strike"); box = decoration("box"); emphasis = decoration("emphasis")
        if let values = object["shadow"] as? [String: Any] {
            shadow = Shadow(color: (values["color"] as? NSNumber)?.int64Value ?? 0x80000000,
                radius: min(10, max(0, number("radius", values, fallback: 3))),
                dx: min(10, max(-10, number("dx", values, fallback: 2))),
                dy: min(10, max(-10, number("dy", values, fallback: 2))))
        }
    }

    public func merging(_ other: HighlightStyle) -> HighlightStyle {
        var result = self
        if other.fill != 0 { result.fill = other.fill; result.fillShape = other.fillShape; result.pillPaddingScale = other.pillPaddingScale }
        if other.textColor != 0 { result.textColor = other.textColor }
        result.bold = bold || other.bold; result.italic = italic || other.italic
        result.underline = other.underline ?? underline
        result.strike = other.strike ?? strike; result.box = other.box ?? box
        result.emphasis = other.emphasis ?? emphasis; result.shadow = other.shadow ?? shadow
        if !other.fontPath.isEmpty { result.fontPath = other.fontPath }
        result.fontSize = other.fontSize ?? fontSize; result.letterSpacing = other.letterSpacing ?? letterSpacing
        return result
    }
}
