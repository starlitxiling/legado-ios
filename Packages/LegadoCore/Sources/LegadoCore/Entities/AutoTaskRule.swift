import Foundation
import GRDB

public struct AutoTaskRule: StorageRow {
    public static let databaseTableName = "auto_task_rules"
    public var id: String = UUID().uuidString
    public var name: String = ""
    public var enable: Bool = true
    public var cron: String? = "*/30 * * * *"
    public var loginUrl: String? = nil
    public var loginUi: String? = nil
    public var loginCheckJs: String? = nil
    public var comment: String? = nil
    public var script: String = ""
    public var header: String? = nil
    public var jsLib: String? = nil
    public var concurrentRate: String? = nil
    public var enabledCookieJar: Bool = true
    public var customOrder: Int = 0
    public var lastRunAt: Int64 = 0
    public var lastResult: String? = nil
    public var lastError: String? = nil
    public var lastLog: String? = nil

    public init() {}

    public init(row: Row) {
        id = row["id"]
        name = row["name"]
        enable = row["enable"]
        cron = row["cron"]
        loginUrl = row["loginUrl"]
        loginUi = row["loginUi"]
        loginCheckJs = row["loginCheckJs"]
        comment = row["comment"]
        script = row["script"]
        header = row["header"]
        jsLib = row["jsLib"]
        concurrentRate = row["concurrentRate"]
        enabledCookieJar = row["enabledCookieJar"]
        customOrder = row["customOrder"]
        lastRunAt = row["lastRunAt"]
        lastResult = row["lastResult"]
        lastError = row["lastError"]
        lastLog = row["lastLog"]
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enable, cron, loginUrl, loginUi, loginCheckJs, comment, script, header, jsLib, concurrentRate, enabledCookieJar, customOrder, lastRunAt, lastResult, lastError, lastLog
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.gsonString(forKey: .id) ?? id
        name = try container.gsonString(forKey: .name) ?? name
        enable = try container.gsonBool(forKey: .enable) ?? enable
        if container.contains(.cron) { cron = try container.gsonString(forKey: .cron) }
        if container.contains(.loginUrl) { loginUrl = try container.gsonString(forKey: .loginUrl) }
        if container.contains(.loginUi) { loginUi = try container.gsonString(forKey: .loginUi) }
        if container.contains(.loginCheckJs) { loginCheckJs = try container.gsonString(forKey: .loginCheckJs) }
        if container.contains(.comment) { comment = try container.gsonString(forKey: .comment) }
        script = try container.gsonString(forKey: .script) ?? script
        if container.contains(.header) { header = try container.gsonString(forKey: .header) }
        if container.contains(.jsLib) { jsLib = try container.gsonString(forKey: .jsLib) }
        if container.contains(.concurrentRate) { concurrentRate = try container.gsonString(forKey: .concurrentRate) }
        enabledCookieJar = try container.gsonBool(forKey: .enabledCookieJar) ?? enabledCookieJar
        customOrder = try container.gsonInt(forKey: .customOrder) ?? customOrder
        lastRunAt = try container.gsonLong(forKey: .lastRunAt) ?? lastRunAt
        if container.contains(.lastResult) { lastResult = try container.gsonString(forKey: .lastResult) }
        if container.contains(.lastError) { lastError = try container.gsonString(forKey: .lastError) }
        if container.contains(.lastLog) { lastLog = try container.gsonString(forKey: .lastLog) }
    }
}

public typealias AutoTaskRuleRepository = Repository<AutoTaskRule>
