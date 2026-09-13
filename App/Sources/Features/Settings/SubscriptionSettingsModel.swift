import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class SubscriptionSettingsModel {
    private(set) var subscriptions: [RuleSub] = []
    private(set) var servers: [Server] = []
    private(set) var isBusy = false
    var errorMessage: String?
    var message: String?
    private let rules: RuleSubRepository
    private let serverRepository: ServerRepository
    private let client: any HttpClient
    private let now: () -> Int64

    init(database: AppDatabase, client: any HttpClient,
         now: @escaping () -> Int64 = GsonDecoding.currentTimeMillis) {
        rules = RuleSubRepository(database: database)
        serverRepository = ServerRepository(database: database)
        self.client = client; self.now = now
    }

    func load() async {
        do {
            subscriptions = try await rules.all().sorted { ($0.customOrder, $0.id) < ($1.customOrder, $1.id) }
            servers = try await serverRepository.all().sorted { ($0.sortNumber, $0.id) < ($1.sortNumber, $1.id) }
        } catch { errorMessage = error.localizedDescription }
    }

    func save(_ subscription: RuleSub, importing: Bool = false) async -> Bool {
        do {
            guard validURL(subscription.url), !subscription.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  [0, 1, 2].contains(subscription.type), subscription.updateInterval >= 0 else {
                throw SettingsValidationError.invalidSubscription
            }
            let existing = try await rules.all()
            guard !existing.contains(where: { $0.url == subscription.url && (importing || $0.id != subscription.id) }) else {
                throw SettingsValidationError.duplicateSubscription
            }
            var value = subscription
            if value.id == 0 { value.id = max(now(), (existing.map(\.id).max() ?? 0) + 1) }
            if importing { try await rules.saveImported([value], at: now()) }
            else { try await rules.upsert(value) }
            errorMessage = nil
            await load()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func save(_ server: Server) async -> Bool {
        do {
            guard !server.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let config = try server.webDavConfig(), validURL(config.url) else {
                throw SettingsValidationError.invalidServer
            }
            var value = server
            if value.id == 0 {
                let existing = try await serverRepository.all()
                value.id = max(now(), (existing.map(\.id).max() ?? 0) + 1)
            }
            try await serverRepository.upsert(value)
            errorMessage = nil
            await load()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func delete(_ subscription: RuleSub) async {
        do { try await rules.delete(subscription); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    func delete(_ server: Server) async {
        do { try await serverRepository.delete(server); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    func importText(_ text: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let importer = SourceImporter(now: now)
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let values: [RuleSub]
            if validURL(text), let url = URL(string: text) {
                values = try await importer.importRuleSubs(from: url, client: client)
            } else { values = try importer.parseRuleSubs(text) }
            for value in values { if !(await save(value, importing: true)) { return } }
            message = "已导入 \(values.count) 条订阅"
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(_ subscription: RuleSub) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let count = try await rules.refresh(subscription, client: client, at: now())
            message = "已更新 \(count) 条规则"
            errorMessage = nil
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    private func validURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme, url.host != nil else { return false }
        return ["http", "https"].contains(scheme.lowercased())
    }
}

private enum SettingsValidationError: LocalizedError {
    case invalidSubscription, duplicateSubscription, invalidServer
    var errorDescription: String? {
        switch self {
        case .invalidSubscription: return "请填写订阅名称、有效的 HTTP 地址及非负更新间隔。"
        case .duplicateSubscription: return "已存在相同地址的订阅。"
        case .invalidServer: return "请填写服务器名称与有效的 WebDAV HTTP 地址。"
        }
    }
}
