import GRDB

/// Kotlin cb664b84d: data/entities/Cookie.kt。
public struct CookieRow: StorageRow {
    public static let databaseTableName = "cookies"
    public var `url`: String = ""
    public var `cookie`: String = ""

    public init() {}
}
