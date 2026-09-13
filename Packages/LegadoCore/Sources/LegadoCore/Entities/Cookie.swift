import Foundation

/// Kotlin cb664b84d: app/src/main/java/io/legado/app/data/entities/Cookie.kt.
public struct Cookie: Codable, Equatable {
    /// Kotlin 默认值：`""`（Cookie.kt:10）。
    public var url: String? = ""
    /// Kotlin 默认值：`""`（Cookie.kt:11）。
    public var cookie: String? = ""

    private enum CodingKeys: String, CodingKey {
        case url
        case cookie
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.url) {
            url = try container.gsonString(forKey: .url)
        }
        if container.contains(.cookie) {
            cookie = try container.gsonString(forKey: .cookie)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(cookie, forKey: .cookie)
    }

}
