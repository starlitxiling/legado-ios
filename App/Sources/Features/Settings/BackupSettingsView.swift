import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

struct BackupSettingsView: View {
    let preferences: AppPreferences
    @State private var selectingDirectory = false
    @State private var message: String?
    private var controls: PreferenceControls { .init(preferences: preferences) }
    private let contentTitles = ["书架与分组", "书签与批注", "书源与订阅源", "规则", "阅读与搜索记录", "阅读记录封面", "设置", "持久封面", "其他封面", "背景图片", "Cookie", "书源运行时变量"]
    private let ignoreTitles = ["阅读配置", "主题模式", "主题配色", "封面配置", "书架布局", "RSS 显示", "线程数", "本地书", "Cookie", "书源运行时变量"]

    var body: some View {
        Form {
            Section("备份") {
                controls.toggle("自动备份", "autoBackup")
                controls.toggle("自动上传 WebDAV", "autoBackupWebDav")
                controls.number("间隔（天）", "autoBackupIntervalDays", range: 1...365)
                controls.toggle("只保留最新本地备份", "onlyLatestBackup")
                controls.toggle("检查新备份", "autoCheckNewBackup")
                Button("选择本地备份文件夹") { selectingDirectory = true }
                Text(preferences.string("backupUri").isEmpty ? "应用内备份目录" : preferences.string("backupUri")).font(.footnote)
                SecureField("本地备份密码", text: controls.string("localPassword"))
                Text("密码仅保存；当前 ZIP 写入器不支持加密，生成的备份仍是未加密 ZIP。").font(.footnote)
            }
            Section("WebDAV") {
                controls.text("目录", "webDavDir")
                controls.text("设备名称", "webDavDeviceName")
                controls.toggle("自动恢复 WebDAV 书籍", "webDavBookAutoRestore")
                controls.toggle("同步阅读进度", "syncBookProgress")
                controls.toggle("增强进度同步", "syncBookProgressPlus")
            }
            Section("备份内容") {
                ForEach(Array(BackupSelection.contentKeys.enumerated()), id: \.element) { index, key in
                    Toggle(contentTitles[index], isOn: Binding(get: { preferences.backupSelection.includes(key) }, set: { enabled in
                        var selection = preferences.backupSelection; selection.values[key] = !enabled; preferences.backupSelection = selection
                    }))
                }
            }
            Section("恢复时忽略") {
                ForEach(Array(BackupSelection.ignoreKeys.enumerated()), id: \.element) { index, key in
                    Toggle(ignoreTitles[index], isOn: Binding(get: { preferences.backupSelection.values[key] == true }, set: { ignored in
                        var selection = preferences.backupSelection; selection.values[key] = ignored; preferences.backupSelection = selection
                    }))
                }
            }
            if let message { Text(message) }
        }
        .navigationTitle("备份设置")
        .fileImporter(isPresented: $selectingDirectory, allowedContentTypes: [.folder]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                preferences.defaults.set(bookmark, forKey: "Legado.backupBookmark")
                preferences.set("backupUri", .string(url.absoluteString))
            } catch { message = error.localizedDescription }
        }
    }
}
