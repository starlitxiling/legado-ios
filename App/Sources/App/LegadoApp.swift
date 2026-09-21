import SwiftUI
import UIKit
import BackgroundTasks
import LegadoCore

@main
struct LegadoApp: App {
    @UIApplicationDelegateAdaptor(LegadoAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppStartupView(appDelegate: appDelegate)
        }
    }
}

struct AppStartupView: View {
    @ObservedObject var appDelegate: LegadoAppDelegate
    @State private var theme = ThemeStore(preferences: .shared)
    @State private var openingFile: LocalFileOpenRequest?

    var body: some View {
        displayedContent
            .modifier(ScriptHostModifier())
            .modifier(ThemeEnvironmentModifier(store: theme))
            .task { appDelegate.openDatabase() }
            .onOpenURL { url in
                guard url.isFileURL else { return }
                openingFile = LocalFileOpenRequest(url: url)
            }
            .sheet(item: $openingFile) { request in
                if let container = appDelegate.container {
                    NavigationStack {
                        LocalImportView(database: container.database, initialURLs: [request.url])
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { openingFile = nil } } }
                    }
                } else { ProgressView("正在打开书库") }
            }
    }

    @ViewBuilder private var displayedContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-localbook-gallery") { LocalBookGalleryView() }
        else if ProcessInfo.processInfo.arguments.contains("-search-gallery") { SearchGalleryView() }
        else if ProcessInfo.processInfo.arguments.contains("-bookshelf-gallery") { BookshelfGalleryView() }
        else if ProcessInfo.processInfo.arguments.contains("-component-gallery") { ComponentGalleryView() }
        else { startupContent }
        #else
        startupContent
        #endif
    }

    private var startupContent: some View {
        Group {
            if let container = appDelegate.container {
                RootTabView(container: container)
                    .environment(container)
                    .modifier(BackupLifecycleModifier(container: container))
            } else if let startupError = appDelegate.startupError {
                VStack(spacing: 16) {
                    EmptyStateView(title: "无法打开书库", systemImage: "exclamationmark.triangle",
                                   message: startupError)
                    Button("重试", action: appDelegate.openDatabase)
                }
            } else {
                ProgressView("正在打开书库")
            }
        }
    }
}

@MainActor
final class LegadoAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    typealias BackgroundRegistration = (@escaping (BGTask) -> Void) -> Bool

    @Published private(set) var container: AppContainer?
    @Published private(set) var startupError: String?
    private let makeContainer: () throws -> AppContainer
    private let registerBackgroundTask: BackgroundRegistration
    private var didRegisterBackgroundTask = false
    private var backgroundTaskRegistered = false

    override convenience init() {
        self.init(makeContainer: AppContainer.live, registerBackgroundTask: { handler in
            BGTaskScheduler.shared.register(forTaskWithIdentifier: BookshelfBackgroundRefresh.identifier,
                                            using: nil, launchHandler: handler)
        })
    }

    init(makeContainer: @escaping () throws -> AppContainer,
         registerBackgroundTask: @escaping BackgroundRegistration) {
        self.makeContainer = makeContainer
        self.registerBackgroundTask = registerBackgroundTask
        super.init()
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if !didRegisterBackgroundTask {
            didRegisterBackgroundTask = true
            backgroundTaskRegistered = registerBackgroundTask { [weak self] task in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    guard let self else { refreshTask.setTaskCompleted(success: false); return }
                    self.openDatabase()
                    guard let container = self.container else {
                        refreshTask.setTaskCompleted(success: false)
                        return
                    }
                    container.backgroundRefresh.handle(refreshTask)
                }
            }
            if !backgroundTaskRegistered {
                NSLog("Background refresh registration failed for %@", BookshelfBackgroundRefresh.identifier)
            }
        }
        return true
    }

    func openDatabase() {
        guard container == nil else { return }
        NSLog("Opening application database")
        do {
            let opened = try makeContainer()
            opened.webService.observe(background: UIApplication.didEnterBackgroundNotification,
                                      foreground: UIApplication.willEnterForegroundNotification)
            opened.databaseLifecycle.observe(background: UIApplication.didEnterBackgroundNotification,
                                             foreground: UIApplication.willEnterForegroundNotification)
            if UIApplication.shared.applicationState == .background {
                opened.webService.enterBackground()
                opened.databaseLifecycle.didEnterBackground()
            }
            NSLog("Application database opened")
            container = opened
            if backgroundTaskRegistered { opened.backgroundRefresh.schedule() }
            startupError = nil
        } catch {
            NSLog("Application database failed to open: %@", error.localizedDescription)
            startupError = error.localizedDescription
        }
    }
}

private struct LocalFileOpenRequest: Identifiable {
    let id = UUID()
    let url: URL
}
