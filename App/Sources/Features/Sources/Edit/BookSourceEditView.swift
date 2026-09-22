import SwiftUI
import LegadoCore

struct BookSourceEditView: View {
    @State private var model: BookSourceEditModel
    @State private var jsonMode = false
    @State private var saving = false
    @State private var section = 0
    @State private var focusedField = "bookSourceUrl"
    @State private var settingsExpanded = false
    @AppStorage("keyboardAssistRows") private var assistRows = 1
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    private let repository: BookSourceRepository
    private let client: any HttpClient
    private let login: SourceLogin
    private let checker: SourceChecker
    private let onSave: () async -> Void

    init(source: BookSource?, repository: BookSourceRepository, client: any HttpClient,
         login: SourceLogin, checker: SourceChecker, onSave: @escaping () async -> Void) {
        _model = State(initialValue: BookSourceEditModel(source: source ?? BookSource(), isNew: source == nil || source?.bookSourceUrl?.isEmpty != false))
        self.repository = repository; self.client = client; self.login = login
        self.checker = checker; self.onSave = onSave
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).padding(8) }
            if jsonMode {
                SourceCodeInput(text: $model.jsonText, field: "json", rows: assistRows).padding(12)
            } else {
                DisclosureGroup("设置", isExpanded: $settingsExpanded) {
                    VStack(spacing: 0) {
                        Picker("书籍类型", selection: field("bookSourceType")) {
                            Text("文本").tag("0"); Text("音频").tag("1"); Text("图片").tag("2")
                        }.frame(height: 48)
                        ForEach([("启用","enabled"),("发现","enabledExplore"),("自动保存 Cookie","enabledCookieJar"),("段评","ruleReview.enabled"),("事件监听","eventListener"),("自定义按钮","customButton")], id: \.1) { label, key in
                            Toggle(label, isOn: Binding(get: { model.value(key) == "true" }, set: { field(key).wrappedValue = $0 ? "true" : "false" })).frame(height: 48)
                        }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 8).background(colors.card, in: RoundedRectangle(cornerRadius: 8)).padding(8)
                HStack(spacing: 0) {
                    ForEach(Array(BookSourceEditModel.groups.enumerated()), id: \.offset) { index, group in
                        Button { section = index; focusedField = group.fields[0] } label: {
                            Text(group.title).font(.system(size: 14)).frame(maxWidth: .infinity).frame(height: 36)
                                .foregroundStyle(section == index ? colors.accent : colors.textPrimary)
                                .overlay(alignment: .bottom) { if section == index { Rectangle().fill(colors.accent).frame(height: 2) } }
                        }.buttonStyle(.plain).accessibilityIdentifier("source.tab." + group.title)
                    }
                }
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(currentFields, id: \.self) { key in
                                    Button(BookSourceEditModel.label(key)) { focusedField = key; proxy.scrollTo(key, anchor: .top) }
                                        .font(.system(size: 13)).foregroundStyle(key == focusedField ? colors.accent : colors.textSecondary)
                                }
                            }.padding(.horizontal, 12).frame(height: 48)
                        }.background(colors.card)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(currentFields, id: \.self) { key in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(BookSourceEditModel.label(key)).font(.system(size: 13)).foregroundStyle(colors.textSecondary)
                                        SourceCodeInput(text: field(key), field: key, rows: assistRows, onFocus: { focusedField = key })
                                            .frame(height: inputHeight(key))
                                    }.id(key)
                                }
                            }.padding(12)
                        }
                    }
                }
            }
        }
        .legadoNavigationTitle("书源编辑")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("JSON 模式", isOn: Binding(get: { jsonMode }, set: { enabled in
                        do { if !enabled { try model.applyJSON(model.jsonText) }; jsonMode = enabled }
                        catch { model.userError = error.presentation(operation: "切换书源编辑模式", subject: model.source.bookSourceName) }
                    }))
                    Picker("辅助键行数", selection: $assistRows) { ForEach(1...5, id: \.self) { Text("\($0) 行").tag($0) } }
                    NavigationLink("调试") { SourceDebugView(source: model.source, client: client) }
                    NavigationLink("登录") { SourceLoginDestination(source: model.source, service: login) }
                    NavigationLink("校验") { CheckSourceView(sources: [model.source], checker: checker) }
                } label: { Image(systemName: "ellipsis") }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(saving) }
        }
        .disabled(saving)
    }

    private var currentFields: [String] {
        let fields = BookSourceEditModel.groups[section].fields
        return section == 0 && model.source.mainJs != nil ? fields + ["mainJs"] : fields
    }
    private func field(_ key: String) -> Binding<String> {
        Binding(get: { model.value(key) }, set: {
            do { try model.setValue($0, for: key); model.userError = nil }
            catch { model.userError = error.presentation(operation: "修改书源字段", subject: [model.source.bookSourceName, key].compactMap { $0 }.joined(separator: " · ")) }
        })
    }
    private func inputHeight(_ key: String) -> CGFloat {
        let lines = model.value(key).components(separatedBy: "\n").count
        return max(48, CGFloat(min(max(2, AppPreferences.shared.integer("sourceEditMaxLine")), lines + 1)) * 20 + 20)
    }

    private func applyJSON() {
        do { try model.applyJSON(model.jsonText); model.userError = nil }
        catch { model.userError = error.presentation(operation: "解析书源 JSON", subject: model.source.bookSourceName) }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await model.save(repository: repository, jsonMode: jsonMode, now: Int64(Date().timeIntervalSince1970 * 1000))
            await onSave(); dismiss()
        } catch { model.userError = error.presentation(operation: "保存书源", subject: [model.source.bookSourceName, model.source.bookSourceUrl].compactMap { $0 }.joined(separator: " · ")) }
    }
}
