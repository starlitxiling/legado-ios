import SwiftUI
import WebKit
import LegadoCore

struct OtherSettingsView: View {
    let container: AppContainer
    let preferences: AppPreferences
    @State private var sources: [BookSource] = []
    @State private var message: String?
    private var controls: PreferenceControls { .init(preferences: preferences) }
    var body: some View {
        Form {
            Section("首页") {
                controls.toggle("启动时刷新书架", "auto_refresh")
                controls.toggle("只更新正在阅读的书", "onlyUpdateRead")
                controls.toggle("启动时继续阅读", "defaultToRead")
                controls.toggle("显示发现", "showDiscovery")
                controls.toggle("发现页快速滚动", "showDiscoveryFastScroller")
                controls.toggle("显示 RSS", "showRss")
                Picker("默认首页", selection: controls.string("defaultHomePage")) {
                    Text("书架").tag("bookshelf"); Text("发现").tag("explore")
                    Text("RSS").tag("rss"); Text("设置").tag("my")
                }
                Picker("语言", selection: controls.string("language")) {
                    Text("跟随系统").tag("auto"); Text("简体中文").tag("zh"); Text("繁体中文").tag("tw"); Text("英语").tag("en")
                }
            }
            Section("网络与图片") {
                controls.text("User-Agent", "userAgent")
                controls.text("自定义 Hosts JSON", "customHosts")
                Text("Hosts 仅保存配置，当前网络层没有自定义 DNS 接口。").font(.footnote)
                controls.toggle("抗锯齿", "antiAlias")
                controls.number("图片缓存容量（MB）", "bitmapCacheSize", range: 0...1024)
                controls.number("保留已读漫画章节（0 不清理）", "imageRetainNum", range: 0...10000)
                controls.number("预下载章节", "preDownloadNum", range: 0...100)
                controls.number("下载线程", "threadCount", range: 1...128)
            }
            Section("阅读与清理") {
                controls.toggle("新书默认启用替换", "replaceEnableDefault")
                controls.toggle("媒体键启动朗读", "readAloudByMediaButton")
                controls.toggle("允许与其他音频混音", "ignoreAudioFocus")
                controls.toggle("自动清理过期缓存", "autoClearExpired")
                controls.toggle("添加书架前提示", "showAddToShelfAlert")
                controls.toggle("使用漫画界面", "showMangaUi")
                Button("清理网络缓存") { URLCache.shared.removeAllCachedResponses(); message = "网络缓存已清理" }
                Button("清理网页缓存") {
                    WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) { message = "网页缓存已清理" }
                }
                Button("压缩数据库") {
                    Task {
                        do { try await container.database.vacuum(); message = "数据库已压缩" }
                        catch { message = error.localizedDescription }
                    }
                }
            }
            Section("书源与调试") {
                TextField("编辑器最大行数", value: controls.integer("sourceEditMaxLine"), format: .number).keyboardType(.numberPad)
                NavigationLink("书源校验") { CheckSourceView(sources: sources, checker: container.sourceChecker) }
                NavigationLink("直链上传规则") { UploadRuleSettingsView(database: container.database) }
                controls.toggle("JS API 需要令牌", "jsSourceApiTokenRequired")
                SecureField("JS API 令牌", text: controls.string("jsSourceApiToken"))
                controls.toggle("记录调试日志", "recordLog")
                controls.toggle("记录 HTTP 日志", "recordHttpLog")
            }
            if let message { Section { Text(message) } }
        }
        .navigationTitle("其他设置")
        .task {
            do { sources = try await container.bookSources.all().map { try DiscoveryStorage.source($0) } }
            catch { message = error.localizedDescription }
        }
    }
}
