import SwiftUI
import WebKit
import LegadoCore

struct GeneralSettingsView: View {
    let preferences: BackupPreferences
    @State private var cacheMessage: String?

    var body: some View {
        Form {
            Section("主题与语言") {
                Picker("主题", selection: string("themeMode")) {
                    Text("跟随系统").tag("0"); Text("浅色").tag("1")
                    Text("深色").tag("2"); Text("E-ink").tag("3")
                }
                Picker("语言", selection: string("language")) {
                    Text("跟随系统").tag("auto"); Text("简体中文").tag("zh")
                    Text("繁体中文").tag("tw")
                    Text("英语").tag("en")
                }
                Text("尚未翻译的界面文字使用简体中文。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("其他设置") {
                Stepper("预下载章节数：\(preferences.integer("preDownloadNum"))", value: integer("preDownloadNum"), in: 0...100)
                Stepper("下载线程数：\(preferences.integer("threadCount"))", value: integer("threadCount"), in: 1...128)
                Text("下载线程数在下次启动后生效。").font(.footnote).foregroundStyle(.secondary)
                Picker("默认书架排序", selection: integer("bookshelfSort")) {
                    Text("最近阅读").tag(0); Text("最近更新").tag(1); Text("书名").tag(2)
                    Text("手动").tag(3); Text("综合").tag(4); Text("作者").tag(5)
                }
                Button("清理网络缓存") {
                    URLCache.shared.removeAllCachedResponses()
                    cacheMessage = "网络缓存已清理"
                }
                Button("清理网页缓存") {
                    let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
                    WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                        cacheMessage = "网页缓存已清理"
                    }
                }
                if let cacheMessage { Text(cacheMessage).foregroundStyle(.secondary) }
            }
            Section("自动备份") {
                Toggle("自动备份", isOn: boolean("autoBackup"))
                Toggle("自动上传 WebDAV", isOn: boolean("autoBackupWebDav"))
                Stepper("备份间隔：\(preferences.integer("autoBackupIntervalDays")) 天", value: integer("autoBackupIntervalDays"), in: 1...365)
                Toggle("本地只保存最新备份", isOn: boolean("onlyLatestBackup"))
                Toggle("同步阅读进度", isOn: boolean("syncBookProgress"))
                TextField("WebDAV 目录", text: string("webDavDir"))
                TextField("设备名", text: string("webDavDeviceName"))
            }
        }
        .navigationTitle("通用设置")
        .onAppear { preferences.reload() }
    }

    private func string(_ key: String) -> Binding<String> {
        Binding(get: { preferences.string(key) }, set: { preferences.set(key, .string($0)) })
    }
    private func integer(_ key: String) -> Binding<Int> {
        Binding(get: { preferences.integer(key) }, set: { preferences.set(key, .int(Int32($0))) })
    }
    private func boolean(_ key: String) -> Binding<Bool> {
        Binding(get: { preferences.boolean(key) }, set: { preferences.set(key, .boolean($0)) })
    }
}
