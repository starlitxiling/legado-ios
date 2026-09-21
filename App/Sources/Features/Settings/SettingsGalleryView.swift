#if DEBUG
import SwiftUI
import LegadoCore

struct SettingsGalleryView: View {
    @State private var container: AppContainer?
    @State private var error: String?
    var body: some View {
        Group {
            if let container {
                NavigationStack {
                    SettingsView(container: container, settingsModel: SettingsViewModel(store: EmptySettingsStore(), httpClient: ReplayHttpClient()))
                }.environment(container)
            } else if let error { Text(error) } else { ProgressView() }
        }.task {
            guard container == nil else { return }
            do {
                let container = try AppContainer.inMemory()
                var rule = AutoTaskRule(); rule.name = "示例任务"; rule.cron = "*/5 * * * *"; rule.script = "'Task completed'"; rule.enable = false
                try await AutoTaskRuleRepository(database: container.database).upsert(rule)
                self.container = container
            } catch { self.error = error.localizedDescription }
        }
    }
}
private struct EmptySettingsStore: KeychainStoring {
    func read(account: String) throws -> String? { nil }
    func write(_ value: String, account: String) throws {}
    func delete(account: String) throws {}
}
#endif
