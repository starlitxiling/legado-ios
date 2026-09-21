import SwiftUI
import UIKit
import LegadoCore

struct ReaderHighlightRulesView: View {
    let repository: HighlightRuleRepository
    let changed: () async -> Void
    @State private var rules: [HighlightRule] = []
    @State private var query = ""
    @State private var draft: HighlightRule?
    @State private var editing = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(rules.filter { query.isEmpty || [$0.name, $0.pattern, $0.group ?? ""].contains { $0.localizedCaseInsensitiveContains(query) } }, id: \.id) { rule in
                    HStack {
                        Button { draft = rule; editing = true } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(rule.name.isEmpty ? rule.pattern : rule.name)
                                Text(rule.pattern).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Toggle("启用 \(rule.name)", isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                            Task { var updated = rule; updated.isEnabled = enabled; await save(updated) }
                        })).labelsHidden()
                    }.swipeActions {
                        Button("删除", role: .destructive) { Task { do { _ = try await repository.delete(rule); await reload(); await changed() } catch { self.error = error.localizedDescription } } }
                    }
                }.onMove { indices, destination in
                    rules.move(fromOffsets: indices, toOffset: destination)
                    for index in rules.indices { rules[index].order = index }
                    Task { do { try await repository.upsert(rules); await changed() } catch { self.error = error.localizedDescription; await reload() } }
                }
            }.searchable(text: $query, prompt: "名称、规则或分组").legadoNavigationTitle("高亮规则")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button("新建", systemImage: "plus") { draft = HighlightRule(); editing = true } }
                    ToolbarItem(placement: .bottomBar) { EditButton().disabled(!query.isEmpty) }
                }.task { await reload() }
                .sheet(isPresented: $editing) {
                    if let draft { ReaderHighlightRuleEditor(rule: draft) { rule in await save(rule); return error == nil } }
                }
        }.alert("高亮规则", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func reload() async {
        do { rules = try await repository.all().sorted { ($0.order, $0.id) < ($1.order, $1.id) } }
        catch { self.error = error.localizedDescription }
    }
    private func save(_ rule: HighlightRule) async {
        do { error = nil; _ = try await repository.upsert(rule); await reload(); await changed() }
        catch { self.error = error.localizedDescription }
    }
}

private struct ReaderHighlightRuleEditor: View {
    @State var rule: HighlightRule
    let save: (HighlightRule) async -> Bool
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    private var style: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(rule.style.utf8)) as? [String: Any]) ?? [:] }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $rule.name)
                    TextField("分组", text: optionalString(\.group))
                    TextField("适用书名或书源（留空适用全部）", text: optionalString(\.scope))
                    TextEditor(text: $rule.pattern).font(.body.monospaced()).frame(minHeight: 80).accessibilityLabel("匹配文本")
                    Toggle("正则表达式", isOn: $rule.isRegex)
                    Toggle("应用于标题", isOn: $rule.applyToTitle)
                    Toggle("应用于正文", isOn: $rule.applyToBody)
                    Toggle("启用", isOn: $rule.isEnabled)
                    TextField("超时（毫秒）", value: $rule.timeoutMillisecond, format: .number).keyboardType(.numberPad)
                }
                Section("样式") {
                    ColorPicker("背景色", selection: color("fill", fallback: 0x80FFFF00))
                    Button("清除背景色") { set("fill", 0) }
                    Picker("背景形状", selection: string("fillShape", fallback: "RECTANGLE")) {
                        ForEach(Array(zip(["RECTANGLE", "ROUNDED", "MARKER", "HALF", "BASELINE", "PILL"], ["矩形", "圆角", "标记笔", "半高", "基线", "胶囊"])), id: \.0) { Text($0.1).tag($0.0) }
                    }
                    ColorPicker("文字颜色", selection: color("textColor", fallback: 0xFF000000))
                    Button("跟随正文颜色") { set("textColor", 0) }
                    Toggle("粗体", isOn: boolean("bold"))
                    Toggle("斜体", isOn: boolean("italic"))
                    NavigationLink("字体") { FontPicker(selection: string("fontPath", fallback: "")) }
                    metric("字号", key: "fontSize", range: 5...100, fallback: 20)
                    metric("字距", key: "letterSpacing", range: -0.5...1, fallback: 0)
                    metric("胶囊留白", key: "pillPaddingScale", range: 0.25...2, fallback: 1)
                }
                Section("装饰") {
                    Toggle("下划线", isOn: decoration("underline"))
                    if style["underline"] != nil {
                        Picker("线型", selection: nestedString("underline", "kind", fallback: "SOLID")) {
                            ForEach(Array(zip(["SOLID", "WAVY", "DASHED", "DOTTED", "DOUBLE"], ["实线", "波浪线", "虚线", "点线", "双线"])), id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                    Toggle("删除线", isOn: decoration("strike"))
                    Toggle("边框", isOn: decoration("box"))
                    Toggle("着重号", isOn: decoration("emphasis"))
                    Toggle("阴影", isOn: decoration("shadow"))
                    NavigationLink("高级样式 JSON") {
                        TextEditor(text: $rule.style).font(.body.monospaced()).padding().accessibilityIdentifier("highlight.styleJSON").legadoNavigationTitle("高级样式")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(saving).legadoNavigationTitle("编辑高亮规则")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { submit() }.disabled(saving) }
                }
        }.interactiveDismissDisabled(saving)
    }
    private func optionalString(_ key: WritableKeyPath<HighlightRule, String?>) -> Binding<String> {
        Binding(get: { rule[keyPath: key] ?? "" }, set: { rule[keyPath: key] = $0 })
    }
    private func set(_ key: String, _ value: Any?) {
        var object = style; object[key] = value
        do { rule.style = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self) }
        catch { self.error = error.localizedDescription }
    }
    private func string(_ key: String, fallback: String) -> Binding<String> {
        Binding(get: { style[key] as? String ?? fallback }, set: { set(key, $0) })
    }
    private func boolean(_ key: String) -> Binding<Bool> {
        Binding(get: { style[key] as? Bool ?? false }, set: { set(key, $0) })
    }
    private func decoration(_ key: String) -> Binding<Bool> {
        Binding(get: { style[key] is [String: Any] }, set: { set(key, $0 ? ["color": 0] : nil) })
    }
    private func nestedString(_ key: String, _ child: String, fallback: String) -> Binding<String> {
        Binding(get: { (style[key] as? [String: Any])?[child] as? String ?? fallback }, set: { value in
            var object = style[key] as? [String: Any] ?? [:]; object[child] = value; set(key, object)
        })
    }
    private func color(_ key: String, fallback: UInt32) -> Binding<Color> {
        Binding(get: { ARGBColor(UInt32(truncatingIfNeeded: (style[key] as? NSNumber)?.int64Value ?? Int64(fallback))).color }, set: { value in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(value).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let argb = UInt32((alpha * 255).rounded()) << 24 | UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
            set(key, Int32(bitPattern: argb))
        })
    }
    private func metric(_ title: String, key: String, range: ClosedRange<Double>, fallback: Double) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(get: { style[key] != nil }, set: { set(key, $0 ? fallback : nil) }))
            if style[key] != nil {
                Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, (style[key] as? NSNumber)?.doubleValue ?? fallback)) }, set: { set(key, $0) }), in: range)
            }
        }
    }
    private func submit() {
        do {
            guard !rule.pattern.isEmpty else { error = "请输入匹配文本。"; return }
            if rule.isRegex { _ = try NSRegularExpression(pattern: rule.pattern) }
            if !rule.style.isEmpty {
                guard try JSONSerialization.jsonObject(with: Data(rule.style.utf8)) is [String: Any] else { error = "样式必须是 JSON 对象。"; return }
            }
            saving = true
            Task { if await save(rule) { dismiss() } else { error = "保存失败，请返回列表查看错误后重试。" }; saving = false }
        } catch { self.error = error.localizedDescription }
    }
}
