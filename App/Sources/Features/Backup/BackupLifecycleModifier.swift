import SwiftUI

struct BackupLifecycleModifier: ViewModifier {
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("themeMode") private var themeMode = "0"
    @AppStorage("language") private var language = "auto"
    @State private var model: BackupViewModel?
    @State private var operation: Task<Void, Never>?
    @State private var restoredStartupProgress = false

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(themeMode == "0" ? nil : themeMode == "2" ? .dark : .light)
            .tint(themeMode == "3" ? .black : Theme.accent)
            .transaction { if themeMode == "3" { $0.animation = nil } }
            .environment(\.locale, language == "auto" ? .current : Locale(identifier: language == "tw" ? "zh-Hant" : language))
            .task { activate() }
            .overlay(alignment: .top) {
                if let name = model?.newBackupName {
                    HStack {
                        Text("发现新备份：\(name)，可到设置中恢复。").font(.caption)
                        Button("关闭") { model?.newBackupName = nil }
                    }.padding().background(.regularMaterial)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { activate() }
                else { operation?.cancel() }
            }
    }

    private func activate() {
        guard operation == nil else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let preferences = BackupPreferences()
                let backup = BackupViewModel(database: container.database, localDeviceID: try SettingsViewModel.localDeviceID(store: KeychainStore()), preferences: preferences)
                model = backup
                let settings = SettingsViewModel(store: KeychainStore(), httpClient: container.httpClient)
                if !settings.address.isEmpty {
                    try backup.configure(credentials: settings.credentials(), httpClient: container.httpClient)
                }
                if preferences.boolean("autoClearExpired") {
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    try await container.database.write { db in
                        try db.execute(sql: "DELETE FROM caches WHERE deadline > 0 AND deadline <= ?", arguments: [timestamp])
                    }
                }
                await backup.checkNewBackup()
                await backup.automaticBackup()
                try Task.checkCancellation()
                if !restoredStartupProgress {
                    restoredStartupProgress = true
                    await backup.synchronizeProgress()
                }
            } catch { model?.errorMessage = error.localizedDescription }
        }
    }
}
