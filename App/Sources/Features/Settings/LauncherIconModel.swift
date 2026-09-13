import Foundation
import Observation

@MainActor protocol LauncherIconClient {
    var supported: Bool { get }
    var alternateNames: [String] { get }
    var currentName: String? { get }
    func change(to name: String?) async throws
}

@Observable @MainActor
final class LauncherIconModel {
    private let client: any LauncherIconClient
    private let save: (String) -> Void
    private(set) var selected: String
    private(set) var changing = false
    private(set) var message: String?
    var available: [String] { client.alternateNames.filter { (1...6).map { "launcher\($0)" }.contains($0) }.sorted() }
    var supported: Bool { client.supported && !available.isEmpty }

    init(client: any LauncherIconClient, save: @escaping (String) -> Void) {
        self.client = client; self.save = save
        selected = client.currentName ?? "ic_launcher"
    }

    func select(_ value: String) async {
        guard !changing else { return }
        guard supported, value == "ic_launcher" || available.contains(value) else {
            message = "当前安装包未提供此备用图标。"; return
        }
        changing = true
        defer { changing = false }
        do {
            try await client.change(to: value == "ic_launcher" ? nil : value)
            selected = client.currentName ?? "ic_launcher"
            save(selected)
            message = "应用图标已更新。"
        } catch { message = error.localizedDescription }
    }
}
