import SwiftUI
import LegadoCore

struct RssSourceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var source: RssSource
    let save: (RssSource) async throws -> Void
    @State private var json = ""
    @State private var jsonMode = false
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        Form {
            if jsonMode {
                Section("完整源 JSON") { TextEditor(text: $json).font(.system(.body, design: .monospaced)).frame(minHeight: 400) }
            } else {
                Section("订阅源") {
                    TextField("名称", text: $source.sourceName)
                    TextField("源地址", text: $source.sourceUrl).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("分组，以逗号分隔", text: optional(\.sourceGroup))
                    Toggle("启用", isOn: $source.enabled)
                    Toggle("直接打开单个地址", isOn: $source.singleUrl)
                    TextField("栏目：名称::url，每行一项", text: optional(\.sortUrl), axis: .vertical)
                    Picker("列表样式", selection: $source.articleStyle) {
                        Text("标准").tag(0); Text("摘要").tag(1); Text("大图").tag(2); Text("图片").tag(3); Text("紧凑").tag(4)
                    }
                }
                Section("解析规则，留空使用 RSS / Atom") {
                    TextField("文章列表", text: optional(\.ruleArticles))
                    TextField("下一页", text: optional(\.ruleNextPage))
                    TextField("标题", text: optional(\.ruleTitle))
                    TextField("链接", text: optional(\.ruleLink))
                    TextField("发布时间", text: optional(\.rulePubDate))
                    TextField("摘要", text: optional(\.ruleDescription))
                    TextField("图片", text: optional(\.ruleImage))
                    TextField("正文", text: optional(\.ruleContent))
                    TextField("正文下一页", text: optional(\.nextContentUrl))
                }
                Section("阅读页面") {
                    Toggle("启用 JavaScript", isOn: $source.enableJs)
                    Toggle("使用文章地址作为 Base URL", isOn: $source.loadWithBaseUrl)
                    TextField("CSS 样式", text: optional(\.style), axis: .vertical)
                    TextField("注入 JavaScript", text: optional(\.injectJs), axis: .vertical)
                    TextField("资源白名单", text: optional(\.contentWhitelist))
                    TextField("资源黑名单", text: optional(\.contentBlacklist))
                    TextField("跳转拦截 JavaScript", text: optional(\.shouldOverrideUrlLoading), axis: .vertical)
                }
                Button("编辑完整 JSON") {
                    do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; json = String(decoding: try encoder.encode(source), as: UTF8.self); jsonMode = true }
                    catch { self.error = String(describing: error) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("编辑 RSS 源")
        .toolbar {
            Button("取消") { dismiss() }
            Button("保存") {
                saving = true
                Task {
                    defer { saving = false }
                    do {
                        let value = jsonMode ? try GsonJSONDecoder().decode(RssSource.self, from: Data(json.utf8)) : source
                        try await save(value); dismiss()
                    } catch { self.error = String(describing: error) }
                }
            }.disabled(saving)
        }
    }
    private func optional(_ key: WritableKeyPath<RssSource, String?>) -> Binding<String> {
        Binding(get: { source[keyPath: key] ?? "" }, set: { source[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
}
