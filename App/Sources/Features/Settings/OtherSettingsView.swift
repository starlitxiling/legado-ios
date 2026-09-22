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
            Section {
                Picker("语言", selection: controls.string("language")) {
                    Text("跟随系统").tag("auto"); Text("简体中文").tag("zh"); Text("繁体中文").tag("tw"); Text("英语").tag("en")
                }
            }
            Section("主界面") {
                controls.toggle("启动时刷新书架", "auto_refresh")
                controls.toggle("仅更新已读完", "onlyUpdateRead")
                controls.toggle("自动跳转最近阅读", "defaultToRead")
                controls.toggle("显示发现", "showDiscovery")
                controls.toggle("发现页快速滚动", "showDiscoveryFastScroller")
                controls.toggle("显示订阅", "showRss")
                Picker("默认首页", selection: controls.string("defaultHomePage")) {
                    Text("书架").tag("bookshelf"); Text("发现").tag("explore")
                    Text("订阅").tag("rss"); Text("我的").tag("my")
                }

            }
            Section("其它设置") {
                TextField("书籍保存位置（应用内文件夹）", text: Binding(get: { preferences.defaults.string(forKey: "Legado.booksFolder") ?? "Books" }, set: { preferences.defaults.set($0, forKey: "Legado.booksFolder") }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("输入应用 Documents 内的文件夹名；更改仅影响新导入书籍，既有书籍保留原位置。").font(.footnote).foregroundStyle(.secondary)
                TextField("源编辑框最大行数", value: controls.integer("sourceEditMaxLine"), format: .number).keyboardType(.numberPad)
                NavigationLink("校验设置") { CheckSourceView(sources: sources, checker: container.sourceChecker) }
                NavigationLink("直链上传规则") { UploadRuleSettingsView(database: container.database) }
                DisclosureGroup("导入文件名规则") {
                    TextEditor(text: controls.string("bookImportFileName")).font(.system(.body, design: .monospaced)).frame(minHeight: 100)
                }

                controls.text("User-Agent", "userAgent")
                controls.text("自定义 Hosts JSON", "customHosts")
                controls.toggle("抗锯齿", "antiAlias")
                controls.number("图片缓存容量（MB）", "bitmapCacheSize", range: 0...1024)
                controls.number("保留已读漫画章节（0 不清理）", "imageRetainNum", range: 0...10000)
                controls.number("预下载章节", "preDownloadNum", range: 0...100)
                controls.number("下载线程", "threadCount", range: 1...128)

                Picker("简繁转换", selection: controls.integer("chineseConverterType")) {
                    Text("不转换").tag(0); Text("转为简体").tag(1); Text("转为繁体").tag(2)
                }
                controls.toggle("新书默认启用替换", "replaceEnableDefault")
                controls.toggle("媒体键启动朗读", "readAloudByMediaButton")
                controls.toggle("允许与其他音频混音", "ignoreAudioFocus")
                controls.toggle("自动清理过期缓存", "autoClearExpired")
                controls.toggle("添加书架前提示", "showAddToShelfAlert")
                controls.toggle("使用漫画界面", "showMangaUi")
                Button("清理无效书籍缓存") {
                    Task {
                        do { message = "已清理 \(try await container.downloads.clearInvalidCache()) 项无效缓存" }
                        catch { message = error.presentation(operation: "清理无效书籍缓存", subject: nil)?.displayText }
                    }
                }
                Button("清理网络缓存") { URLCache.shared.removeAllCachedResponses(); message = "网络缓存已清理" }
                Button("清理网页缓存") {
                    WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast) { message = "网页缓存已清理" }
                }
                Button("压缩数据库") {
                    Task {
                        do { try await container.database.vacuum(); message = "数据库已压缩" }
                        catch { message = error.presentation(operation: "压缩数据库", subject: nil)?.displayText }
                    }
                }

                controls.toggle("JS API 需要令牌", "jsSourceApiTokenRequired")
                SecureField("JS API 令牌", text: controls.string("jsSourceApiToken"))
                controls.toggle("记录调试日志", "recordLog")
                controls.toggle("记录 HTTP 日志", "recordHttpLog")
            }
            if let message { Section { Text(message) } }
        }
        .legadoNavigationTitle("其它设置")
        .task {
            do { sources = try await container.bookSources.all().map { try DiscoveryStorage.source($0) } }
            catch { message = error.presentation(operation: "加载书源设置", subject: nil)?.displayText }
        }
    }
}
