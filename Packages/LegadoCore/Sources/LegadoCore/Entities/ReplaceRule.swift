import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/ReplaceRule.kt.
public struct ReplaceRule: Codable, Equatable {
    /// Kotlin 默认值：`System.currentTimeMillis()`（ReplaceRule.kt:28）。
    public var id: Int64
    /// Kotlin 默认值：`""`（ReplaceRule.kt:31）。
    public var name: String? = ""
    /// Kotlin 默认值：`null`（ReplaceRule.kt:33）。
    public var group: String? = nil
    /// Kotlin 默认值：`""`（ReplaceRule.kt:36）。
    public var pattern: String? = ""
    /// Kotlin 默认值：`""`（ReplaceRule.kt:39）。
    public var replacement: String? = ""
    /// Kotlin 默认值：`null`（ReplaceRule.kt:41）。
    public var scope: String? = nil
    /// Kotlin 默认值：`false`（ReplaceRule.kt:44）。
    public var scopeTitle: Bool = false
    /// Kotlin 默认值：`false`（ReplaceRule.kt:47）。
    public var scopeSource: Bool = false
    /// Kotlin 默认值：`true`（ReplaceRule.kt:50）。
    public var scopeContent: Bool = true
    /// Kotlin 默认值：`null`（ReplaceRule.kt:52）。
    public var excludeScope: String? = nil
    /// Kotlin 默认值：`true`（ReplaceRule.kt:55）。
    public var isEnabled: Bool = true
    /// Kotlin 默认值：`true`（ReplaceRule.kt:58）。
    public var isRegex: Bool = true
    /// Kotlin 默认值：`3000L`（ReplaceRule.kt:61）。
    public var timeoutMillisecond: Int64 = 3000
    /// Kotlin 默认值：`Int.MIN_VALUE`（ReplaceRule.kt:64）。
    public var order: Int = -2147483648
    /// Kotlin 默认值：`null`（ReplaceRule.kt:70）。
    public var previewText: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case group
        case pattern
        case replacement
        case scope
        case scopeTitle
        case scopeSource
        case scopeContent
        case excludeScope
        case isEnabled
        case isRegex
        case timeoutMillisecond
        case order
        case previewText
    }

    public init(now: Int64 = GsonDecoding.currentTimeMillis()) {
        id = now
    }

    public init(from decoder: Decoder) throws {
        self.init(now: GsonDecoding.time(from: decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.gsonLong(forKey: .id) ?? id
        if container.contains(.name) {
            name = try container.gsonString(forKey: .name)
        }
        if container.contains(.group) {
            group = try container.gsonString(forKey: .group)
        }
        if container.contains(.pattern) {
            pattern = try container.gsonString(forKey: .pattern)
        }
        if container.contains(.replacement) {
            replacement = try container.gsonString(forKey: .replacement)
        }
        if container.contains(.scope) {
            scope = try container.gsonString(forKey: .scope)
        }
        scopeTitle = try container.gsonBool(forKey: .scopeTitle) ?? scopeTitle
        scopeSource = try container.gsonBool(forKey: .scopeSource) ?? scopeSource
        scopeContent = try container.gsonBool(forKey: .scopeContent) ?? scopeContent
        if container.contains(.excludeScope) {
            excludeScope = try container.gsonString(forKey: .excludeScope)
        }
        isEnabled = try container.gsonBool(forKey: .isEnabled) ?? isEnabled
        isRegex = try container.gsonBool(forKey: .isRegex) ?? isRegex
        timeoutMillisecond = try container.gsonLong(forKey: .timeoutMillisecond) ?? timeoutMillisecond
        order = try container.gsonInt(forKey: .order) ?? order
        if container.contains(.previewText) {
            previewText = try container.gsonString(forKey: .previewText)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(group, forKey: .group)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(replacement, forKey: .replacement)
        try container.encode(scope, forKey: .scope)
        try container.encode(scopeTitle, forKey: .scopeTitle)
        try container.encode(scopeSource, forKey: .scopeSource)
        try container.encode(scopeContent, forKey: .scopeContent)
        try container.encode(excludeScope, forKey: .excludeScope)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isRegex, forKey: .isRegex)
        try container.encode(timeoutMillisecond, forKey: .timeoutMillisecond)
        try container.encode(order, forKey: .order)
        try container.encode(previewText, forKey: .previewText)
    }

}
