import Foundation
import GRDB

public struct HttpTTS: Codable, Equatable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "httpTTS"
    public var id: Int64
    public var name: String
    public var url: String
    public var contentType: String?
    public var pauseDuration = 0
    public var concurrentRate: String? = "0"
    public var loginUrl: String?
    public var loginUi: String?
    public var header: String?
    public var jsLib: String?
    public var enabledCookieJar: Bool? = false
    public var loginCheckJs: String?
    public var lastUpdateTime: Int64
    public init(id: Int64, name: String, url: String) {
        self.id = id; self.name = name; self.url = url; lastUpdateTime = id
    }
    public init(row: Row) {
        id = row["id"]; name = row["name"]; url = row["url"]
        contentType = row["contentType"]; pauseDuration = row["pauseDuration"]
        concurrentRate = row["concurrentRate"]; loginUrl = row["loginUrl"]; loginUi = row["loginUi"]
        header = row["header"]; jsLib = row["jsLib"]; enabledCookieJar = row["enabledCookieJar"]
        loginCheckJs = row["loginCheckJs"]; lastUpdateTime = row["lastUpdateTime"]
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, url, contentType, pauseDuration, concurrentRate, loginUrl, loginUi, header, jsLib, enabledCookieJar, loginCheckJs, lastUpdateTime
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.gsonLong(forKey: .id) ?? GsonDecoding.time(from: decoder)
        name = try c.gsonString(forKey: .name) ?? ""; url = try c.gsonString(forKey: .url) ?? ""
        contentType = try c.gsonString(forKey: .contentType)
        pauseDuration = try c.gsonInt(forKey: .pauseDuration) ?? 0
        concurrentRate = c.contains(.concurrentRate) ? try c.gsonString(forKey: .concurrentRate) : "0"
        loginUrl = try c.gsonString(forKey: .loginUrl); loginUi = try c.gsonString(forKey: .loginUi)
        header = try c.gsonString(forKey: .header); jsLib = try c.gsonString(forKey: .jsLib)
        enabledCookieJar = c.contains(.enabledCookieJar) ? try c.gsonBool(forKey: .enabledCookieJar) : false
        loginCheckJs = try c.gsonString(forKey: .loginCheckJs)
        lastUpdateTime = try c.gsonLong(forKey: .lastUpdateTime) ?? GsonDecoding.time(from: decoder)
    }
}
