import SwiftUI

struct AppLogView: View {
    @State private var entries: [AppLogStore.Entry] = []
    @State private var preferences = AppPreferences.shared
    let store: AppLogStore

    init(store: AppLogStore = .shared) { self.store = store }

    var body: some View {
        List {
            Toggle("记录 HTTP 日志", isOn: Binding(get: { preferences.boolean("recordHttpLog") }, set: { preferences.set("recordHttpLog", .boolean($0)) }))
            if entries.isEmpty { Text("暂无日志").foregroundStyle(.secondary) }
            ForEach(entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                    Text(entry.message).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .legadoNavigationTitle("日志")
        .toolbar {
            Button("清空") { store.clear(); entries = [] }.disabled(entries.isEmpty)
            ShareLink("分享", item: entries.map { $0.date.formatted() + " " + $0.message }.joined(separator: "\n"))
                .disabled(entries.isEmpty)
        }
        .task {
            while !Task.isCancelled {
                entries = store.snapshot()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
}
