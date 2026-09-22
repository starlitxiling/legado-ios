import SwiftUI
import LegadoCore
import UserNotifications

struct SettingsView: View {
    let container: AppContainer
    @State private var model: SettingsViewModel
    @State private var backupModel: BackupViewModel?
    @State private var preferences = AppPreferences.shared
    @State private var showsExit = false
    private var controls: PreferenceControls { .init(preferences: preferences) }
    @Environment(ThemeStore.self) private var themeStore

    init(container: AppContainer, settingsModel: SettingsViewModel? = nil) {
        self.container = container
        _model = State(initialValue: settingsModel ?? SettingsViewModel(store: KeychainStore(), httpClient: container.httpClient))
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SourcesView(repository: container.bookSources, replaceRules: container.replaceRules,
                        httpClient: ImportHttpClient(), sourceLogin: container.sourceLogin, sourceChecker: container.sourceChecker)
                } label: { row("书源管理", "导入、编辑和校验书源", "tray.full") }
                NavigationLink { AutoTasksView(container: container) } label: { row("定时任务", "管理脚本与定时更新", "clock") }
                Toggle(isOn: Binding(get: { preferences.boolean("autoTaskService") }, set: { enabled in
                    preferences.set("autoTaskService", .boolean(enabled))
                    if enabled { Task {
                        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]); await container.autoTasks.runDue() }
                        catch { container.autoTasks.userError = error.presentation(operation: "申请定时任务通知权限") }
                    } }
                })) { row("运行定时任务", "后台时间由 iOS 调度", "play.rectangle") }
                NavigationLink { TxtTocRulesView(database: container.database) } label: { row("TXT 目录规则", "本地书籍目录识别", "list.bullet") }
                NavigationLink { ReplaceRulesView(repository: container.replaceRules, httpClient: ImportHttpClient()) } label: { row("替换管理", "净化和替换正文", "arrow.2.squarepath") }
                NavigationLink { DictRulesView(database: container.database) } label: { row("字典规则", "阅读时查询选中的文字", "character.book.closed") }
                VStack(alignment: .leading, spacing: 10) {
                    row("主题模式", "选择白天、夜间或墨水屏", "paintpalette")
                    Picker("主题模式", selection: Binding(get: { themeStore.mode }, set: { themeStore.mode = $0 })) {
                        Text("系统").tag(ThemeMode.system); Text("白天").tag(ThemeMode.light)
                        Text("夜间").tag(ThemeMode.dark); Text("墨水屏").tag(ThemeMode.eInk)
                    }.pickerStyle(.segmented).accessibilityIdentifier("settings.themeMode")
                }
                HStack {
                    NavigationLink { WebServiceView(model: container.webService) } label: { row("Web 服务", "局域网访问书架", "globe") }
                    Toggle("Web 服务", isOn: Binding(get: { container.webService.isRunning || container.webService.isStarting }, set: { enabled in
                        if enabled { container.webService.start() } else { container.webService.stop() }
                    })).labelsHidden()
                }
                Toggle(isOn: .constant(false)) { row("MCP 服务", "本轮暂不启用", "globe") }.disabled(true)
            }
            Section("设置") {
                NavigationLink { BackupView(container: container, settings: model, model: $backupModel) } label: { row("备份与恢复", "WebDAV 与本地备份", "externaldrive") }
                NavigationLink { ThemeSettingsView(preferences: preferences) } label: { row("主题设置", "图标、字体、封面和配色", "paintpalette") }
                NavigationLink { OtherSettingsView(container: container, preferences: preferences) } label: { row("其它设置", "主界面、网络与存储", "slider.horizontal.3") }
            }
            Section("其他") {
                NavigationLink { LibraryHistoryView(container: container, bookmarks: true) } label: { row("书签", "所有书籍的书签", "bookmark") }
                NavigationLink { LibraryHistoryView(container: container, bookmarks: false) } label: { row("阅读记录", "最近阅读与阅读时长", "clock.arrow.circlepath") }
                NavigationLink { LibraryFilesView(container: container) } label: { row("文件管理", "导入、分享和管理本地书籍", "folder") }
                NavigationLink { AboutView() } label: { row("关于", SettingsViewModel.version(), "info.circle") }
                Button { showsExit = true } label: { row("退出", "结束本次阅读", "rectangle.portrait.and.arrow.right") }
            }
        }.listStyle(.plain)
        .legadoNavigationTitle("我的")
        .onAppear { preferences.reload() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { Link("帮助", destination: URL(string: "https://github.com/gedoor/legado/wiki")!) } label: { Image(systemName: "ellipsis") } } }
        .alert("退出", isPresented: $showsExit) {
            Button("停止服务") { container.webService.stop(); container.audioPlayback.stop() }
            Button("取消", role: .cancel) {}
        } message: { Text("可停止当前服务。关闭应用请使用系统应用切换器。") }
    }
    private func row(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 24)).frame(width: 24).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16)).foregroundStyle(.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 5)
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            LabeledContent("Legado", value: SettingsViewModel.version())
            Section("开源许可") {
                ForEach(OpenSourceLicense.all, id: \.name) { license in
                    NavigationLink {
                        ScrollView { Text(license.text).textSelection(.enabled).padding() }
                            .legadoNavigationTitle(license.name)
                    } label: {
                        LabeledContent(license.name, value: license.kind)
                    }
                }
            }
        }
        .legadoNavigationTitle("关于")
    }
}
