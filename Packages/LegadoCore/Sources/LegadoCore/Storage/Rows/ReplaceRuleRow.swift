import GRDB

/// Kotlin cb664b84d: data/entities/ReplaceRule.kt。
public struct ReplaceRuleRow: StorageRow {
    public static let databaseTableName = "replace_rules"
    public var `id`: Int64? = nil
    public var `name`: String = ""
    public var `group`: String? = nil
    public var `pattern`: String = ""
    public var `replacement`: String = ""
    public var `scope`: String? = nil
    public var `scopeTitle`: Bool = false
    public var `scopeSource`: Bool = false
    public var `scopeContent`: Bool = true
    public var `excludeScope`: String? = nil
    public var `isEnabled`: Bool = true
    public var `isRegex`: Bool = true
    public var `timeoutMillisecond`: Int64 = 3000
    public var previewText: String? = nil
    public var `order`: Int = Int(Int32.min)

    public init() {}

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum CodingKeys: String, CodingKey {
        case previewText
        case `id`
        case `name`
        case `group`
        case `pattern`
        case `replacement`
        case `scope`
        case `scopeTitle`
        case `scopeSource`
        case `scopeContent`
        case `excludeScope`
        case `isEnabled`
        case `isRegex`
        case `timeoutMillisecond`
        case `order` = "sortOrder"
    }
}
