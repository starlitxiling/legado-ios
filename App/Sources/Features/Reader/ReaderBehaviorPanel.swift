import SwiftUI

struct ReaderBehaviorPanel: View {
    @Binding var configuration: ReaderBehaviorConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ForEach(ReaderBehaviorConfiguration.definitions, id: \.key) { item in
                    switch item.kind {
                    case .toggle:
                        VStack(alignment: .leading) {
                            Toggle(item.title, isOn: Binding(get: { configuration.boolean(item.key) }, set: { configuration.set(item.key, .boolean($0)) }))
                                .disabled(item.key == "volumeKeyPage" || item.key == "volumeKeyPageOnPlay")
                            if item.key == "volumeKeyPage" || item.key == "volumeKeyPageOnPlay" {
                                Text("iOS 不支持拦截音量键").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    case .choice(_, let choices):
                        Picker(item.title, selection: Binding(get: { configuration.string(item.key) }, set: { configuration.set(item.key, .string($0)) })) {
                            ForEach(choices, id: \.0) { Text($0.1).tag($0.0) }
                        }.accessibilityIdentifier(item.key)
                    case .number(_, let range, let step):
                        VStack(alignment: .leading) {
                            Text("\(item.title)：\(configuration.integer(item.key))")
                            Slider(value: Binding(get: { Double(configuration.integer(item.key)) }, set: { configuration.set(item.key, .int(Int32($0))) }),
                                   in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step)).accessibilityLabel(item.title)
                        }.disabled(item.key == "mouseWheelScrollSpeed" && !configuration.boolean("mouseWheelPage"))
                    case .action:
                        NavigationLink(item.title) {
                            switch item.key {
                            case "clickRegionalConfig": ReaderTouchConfigurationView()
                            case "customPageKey": ReaderKeyboardConfigurationView()
                            case "customTextMenu": ReaderMenuConfigurationView(selection: true)
                            default: ReaderMenuConfigurationView(selection: false)
                            }
                        }
                    }
                }
            }.legadoNavigationTitle("阅读设置")
                .toolbar { Button("完成") { dismiss() } }
        }
    }
}

struct ReaderTouchConfigurationView: View {
    @State private var actions = ReaderTouchMap.load()
    private let labels = ["左上", "中上", "右上", "左中", "中中", "右中", "左下", "中下", "右下"]
    var body: some View {
        VStack(spacing: 16) {
            Text("至少保留一个区域用于打开菜单").font(.callout)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(0..<9) { index in
                    Menu {
                        ForEach(ReaderTapAction.allCases, id: \.rawValue) { action in
                            Button(action.title) {
                                actions[index] = action; actions = ReaderTouchMap.normalized(actions); ReaderTouchMap.save(actions)
                            }
                        }
                    } label: {
                        VStack(spacing: 12) { Text(labels[index]).font(.caption); Text(actions[index].title).font(.callout) }
                            .frame(maxWidth: .infinity, minHeight: 100).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }.accessibilityLabel("\(labels[index])：\(actions[index].title)")
                }
            }
            Button("恢复默认") { actions = ReaderTouchMap.defaultActions; ReaderTouchMap.save(actions) }
            Spacer()
        }.padding().legadoNavigationTitle("点击区域设置")
    }
}

struct ReaderKeyboardConfigurationView: View {
    @AppStorage("prevKeys") private var previous = ""
    @AppStorage("nextKeys") private var next = ""
    @State private var recording: Bool?
    @FocusState private var capturing: Bool
    var body: some View {
        Form {
            Section("连接外接键盘后录入按键") {
                TextField("上一页按键编号", text: $previous)
                TextField("下一页按键编号", text: $next)
                Button(recording == false ? "请按上一页按键…" : "录入上一页按键") { recording = false; capturing = true }
                Button(recording == true ? "请按下一页按键…" : "录入下一页按键") { recording = true; capturing = true }
                Text("默认使用方向键、Page Up / Page Down 和空格。自定义按键沿用 Android 编号，以逗号分隔，便于同步备份。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("恢复默认") { previous = ""; next = ""; recording = nil }
            }
        }.focusable().focused($capturing).onKeyPress { press in
            guard let recording, let code = ReaderKeyboard.androidCode(character: String(press.key.character)) else { return .ignored }
            let current = recording ? next : previous
            let value = current.isEmpty ? "\(code)" : current + ",\(code)"
            if recording { next = value } else { previous = value }
            self.recording = nil
            return .handled
        }.legadoNavigationTitle("自定义翻页按键")
    }
}

struct ReaderMenuConfigurationView: View {
    let selection: Bool
    @State private var value = ReaderMenuPartition(primary: [], more: [])
    @State private var error: UserFacingError?
    private var labels: [String: String] { Dictionary(uniqueKeysWithValues: selection ? ReaderMenuPartition.textActions : ReaderMenuPartition.readerActions) }
    var body: some View {
        List {
            Section(selection ? "选择栏" : "主菜单") {
                ForEach(value.primary, id: \.self) { key in
                    HStack { Text(labels[key] ?? key); Spacer(); Button("移至更多", systemImage: "arrow.down") { value.primary.removeAll { $0 == key }; value.more.append(key); save() }.labelStyle(.iconOnly) }
                }.onMove { value.primary.move(fromOffsets: $0, toOffset: $1); save() }
            }
            Section("更多") {
                ForEach(value.more, id: \.self) { key in
                    HStack { Text(labels[key] ?? key); Spacer(); Button("移至主菜单", systemImage: "arrow.up") { value.more.removeAll { $0 == key }; value.primary.append(key); save() }.labelStyle(.iconOnly) }
                }.onMove { value.more.move(fromOffsets: $0, toOffset: $1); save() }
            }
        }.environment(\.editMode, .constant(.active))
            .legadoNavigationTitle(selection ? "选择菜单" : "阅读菜单")
            .onAppear { value = .load(selection: selection) }
            .alert("菜单保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error?.displayText ?? "") }
    }
    private func save() { do { try value.save(selection: selection) } catch { self.error = error.presentation(operation: "保存阅读菜单", subject: selection ? "文本选择菜单" : "阅读菜单") } }
}
