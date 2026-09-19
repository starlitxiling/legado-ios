import SwiftUI
import LegadoCore

struct BookshelfLayoutSettingsView: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    private var controls: PreferenceControls { .init(preferences: preferences) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("分组样式", selection: controls.integer("bookGroupStyle")) {
                    Text("标签").tag(0); Text("文件夹").tag(1)
                }.accessibilityIdentifier("bookshelf.groupStyle")
                Picker("阅读进度", selection: Binding(get: { preferences.bookshelfProgressMode.rawValue }, set: {
                    preferences.set("bookshelfReadProgressMode", .int(Int32(clamping: $0)))
                    preferences.set("showBookshelfReadProgress", .boolean($0 != 0))
                })) {
                    ForEach(BookshelfProgressMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                controls.toggle("显示未读标志", "showUnread")
                controls.toggle("显示上次更新时间", "showLastUpdateTime")
                controls.toggle("显示等待更新数量", "showWaitUpCount")
                controls.toggle("显示快速滚动条", "showBookshelfFastScroller")
                controls.toggle("最近阅读", "showBookshelfRecentReading")
                controls.toggle("数量统计", "showBookshelfStats")
                Picker("视图", selection: controls.integer("bookshelfLayout")) {
                    ForEach(BookshelfLayout.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.accessibilityIdentifier("bookshelf.layout")
                Picker("书名", selection: controls.integer("showBooknameLayout")) {
                    Text("显示").tag(0); Text("隐藏").tag(1)
                }
                Picker("排序", selection: controls.integer("bookshelfSort")) {
                    ForEach(Array(["按阅读时间", "按更新时间", "按书名", "手动排序", "综合排序", "按作者"].enumerated()), id: \.offset) {
                        Text($0.element).tag($0.offset)
                    }
                }
                VStack(alignment: .leading) {
                    Text("书架边距：\(preferences.integer("bookshelfMargin"))")
                    Slider(value: Binding(get: { Double(preferences.integer("bookshelfMargin")) }, set: {
                        preferences.set("bookshelfMargin", .int(Int32($0.rounded())))
                    }), in: 0...40, step: 1)
                }
            }
            .legadoNavigationTitle("书架布局")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("确定") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

extension AppPreferences {
    var bookshelfProgressMode: BookshelfProgressMode {
        let mode: Int?
        if case let .int(value)? = snapshot["bookshelfReadProgressMode"] { mode = Int(value) }
        else if case let .string(value)? = snapshot["bookshelfReadProgressMode"] { mode = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { mode = nil }
        let legacy: Bool?
        if case let .boolean(value)? = snapshot["showBookshelfReadProgress"] { legacy = value }
        else if case let .string(value)? = snapshot["showBookshelfReadProgress"] { legacy = value == "true" ? true : value == "false" ? false : nil }
        else { legacy = nil }
        return .init(storedMode: mode, legacyEnabled: legacy)
    }
}
