import SwiftUI
import LegadoCore

struct CookieManagementView: View {
    let service: SourceLogin
    @State private var domains: [CookieRow] = []
    @State private var errorMessage: String?
    var body: some View {
        List {
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            ForEach(domains, id: \.url) { row in
                HStack {
                    Text(row.url)
                    Spacer()
                    Button("清除", role: .destructive) {
                        Task {
                            do { try await service.clearCookies(domain: row.url); await load() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .navigationTitle("Cookie 管理")
        .overlay { if domains.isEmpty && errorMessage == nil { ContentUnavailableView("没有 Cookie", systemImage: "tray") } }
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        do { domains = try await service.cookieDomains(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
