import Foundation

public enum AutoTaskRunner {
    public static func run(_ rule: AutoTaskRule, database: AppDatabase, client: any HttpClient,
                           secrets: any SourceSecretStore = MemorySourceSecretStore(),
                           action: ([String: Any]) async throws -> String) async throws -> AutoTaskRule {
        var updated = rule
        let started = Date()
        do {
            let work = Task.detached { () throws -> Any? in
                var source = BookSource(); source.bookSourceUrl = "autoTask:" + rule.id; source.bookSourceName = rule.name
                source.loginUrl = rule.loginUrl; source.loginUi = rule.loginUi; source.loginCheckJs = rule.loginCheckJs
                source.header = rule.header; source.jsLib = rule.jsLib; source.concurrentRate = rule.concurrentRate; source.enabledCookieJar = rule.enabledCookieJar
                let session = SourceSessionHttpClient(source: source, database: database, client: client, secrets: secrets)
                let bridge = SourceScriptBridge(source: source, database: database, secrets: secrets)
                let headers = try source.header.flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] } ?? [:]
                let engine = JsEngine(baseUrl: source.bookSourceUrl ?? "", httpClient: session,
                    networkSource: .init(key: source.bookSourceUrl, headers: headers, enabledCookieJar: source.enabledCookieJar ?? true, concurrentRate: source.concurrentRate))
                engine.sourceBindingInstaller = { [weak engine] in try bridge.install(in: $0, engine: engine, javaAliases: true) }
                engine.libraryInitializer = { context in if let library = source.jsLib { context.evaluateScript(library) } }
                var script = rule.script.trimmingCharacters(in: .whitespacesAndNewlines)
                if script.lowercased().hasPrefix("@js:") { script = String(script.dropFirst(4)) }
                else if script.lowercased().hasPrefix("<js>"), script.lowercased().hasSuffix("</js>") { script = String(script.dropFirst(4).dropLast(5)) }
                guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw JsEngineError.exception("Task script is empty") }
                return try engine.evaluateScript(script)
            }
            let raw = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            var normalized = raw
            if let string = raw as? String, let data = string.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) { normalized = object }
            let actions: [[String: Any]]
            if let list = normalized as? [[String: Any]] { actions = list }
            else if let object = normalized as? [String: Any] { actions = object["actions"] as? [[String: Any]] ?? (object["type"] == nil ? [] : [object]) }
            else { actions = [] }
            var logs: [String] = []
            for item in actions {
                try Task.checkCancellation()
                guard ["notify","refreshtoc"].contains((item["type"] as? String ?? "").lowercased()) else { throw JsEngineError.exception("Unsupported automatic task action") }
                logs.append(try await action(item))
            }
            updated.lastResult = String(ruleText(raw).prefix(500)); updated.lastError = nil
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            let lines = ["[OK] " + String(elapsed) + "ms"] + logs + [updated.lastResult ?? ""]
            updated.lastLog = String(lines.joined(separator: "\n").prefix(4000))
        } catch {
            try Task.checkCancellation()
            updated.lastResult = nil; updated.lastError = String(error.localizedDescription.prefix(1000))
            updated.lastLog = "[ERROR] " + (updated.lastError ?? "")
        }
        updated.lastRunAt = Int64(Date().timeIntervalSince1970*1000)
        try await AutoTaskRuleRepository(database: database).upsert(updated)
        return updated
    }
}
