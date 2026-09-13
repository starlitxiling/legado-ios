import SwiftUI
import UIKit
import LegadoCore

@main
struct LegadoApp: App {
    @State private var container: AppContainer?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootTabView(container: container)
                        .environment(container)
                } else if let startupError {
                    VStack(spacing: 16) {
                        EmptyStateView(title: "无法打开书库", systemImage: "exclamationmark.triangle",
                                       message: startupError)
                        Button("重试", action: openDatabase)
                    }
                } else {
                    ProgressView("正在打开书库")
                }
            }
            .tint(Theme.accent)
            .task { if container == nil { openDatabase() } }
        }
    }

    @MainActor
    private func openDatabase() {
        do {
            let opened = try AppContainer.live()
            opened.databaseLifecycle.observe(background: UIApplication.didEnterBackgroundNotification,
                                             foreground: UIApplication.willEnterForegroundNotification)
            if UIApplication.shared.applicationState == .background {
                opened.databaseLifecycle.didEnterBackground()
            }
            container = opened
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }
}
