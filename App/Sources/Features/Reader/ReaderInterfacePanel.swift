import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import LegadoCore

@MainActor
struct ReaderInterfacePanel: View {
    let store: ReaderStyleStore
    let apply: (ReaderSettings) async -> Void
    @State private var draft: ReaderSettings
    @State private var work: Task<Void, Never>?
    @State private var rendering: Task<Void, Never>?
    @State private var error: UserFacingError?
    @State private var customizing = false
    @State private var importing = false
    @State private var importingImage = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var exporting = false
    @State private var document = ReaderStyleDocument(data: Data())
    @State private var linkedMargins = true
    @AppStorage("chineseConverterType") private var chineseConverterType = 0
    @Environment(\.dismiss) private var dismiss

    init(store: ReaderStyleStore, settings: ReaderSettings, apply: @escaping (ReaderSettings) async -> Void) {
        self.store = store; self.apply = apply; _draft = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Menu("字重") {
                                Picker("字重", selection: config(\.textBold)) {
                                    Text("正常").tag(0); Text("粗体").tag(1); Text("细体").tag(2)
                                }
                            }
                            NavigationLink("字体") { FontPicker(selection: config(\.textFont)) }
                            Menu("缩进") {
                                ForEach(0..<5) { count in
                                    Button("\(count) 字") { config(\.paragraphIndent).wrappedValue = String(repeating: "\u{3000}", count: count) }
                                }
                            }
                            Menu("繁简转换") {
                                Picker("繁简转换", selection: $chineseConverterType) {
                                    Text("不转换").tag(0); Text("转简体").tag(1); Text("转繁体").tag(2)
                                }
                            }
                            NavigationLink("边距") { margins }
                            NavigationLink("信息") { information }
                            NavigationLink("下划线") { underline }
                        }.font(.system(size: 14)).buttonStyle(.bordered)
                    }
                    HStack {
                        ColorPicker("文字颜色", selection: color(textColorPath))
                        ColorPicker("背景颜色", selection: backgroundColor)
                    }
                    NavigationLink("背景图片") { backgroundImages }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
                    slider("字号", value: number(\.textSize), range: 5...50, step: 1)
                    slider("字间距", value: Binding(get: { (draft.letterSpacing + 0.5) * 100 },
                        set: { setting(\.letterSpacing).wrappedValue = $0 / 100 - 0.5 }), range: 0...100, step: 1)
                    slider("行距", value: number(\.lineSpacingExtra), range: -10...40, step: 1, divisor: 10)
                    slider("段距", value: number(\.paragraphSpacing), range: 0...20, step: 1, divisor: 10)
                    Picker("翻页动画", selection: config(draft.isEInk ? \.pageAnimEInk : \.pageAnim)) {
                        Text("覆盖").tag(0); Text("滑动").tag(1); Text("仿真").tag(2); Text("滚动").tag(3); Text("无").tag(4)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("样式（长按自定义）").font(.caption)
                        Spacer(minLength: 4)
                        Toggle("共用布局", isOn: Binding(get: { store.sharedLayout }, set: { enabled in
                            enqueue { try await store.setSharedLayout(enabled); await adoptStyle() }
                        })).font(.caption).fixedSize()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(store.styles.enumerated()), id: \.offset) { index, style in
                                Button {
                                    enqueue { try await store.select(index); await adoptStyle() }
                                } label: {
                                    Text("文").font(.system(size: 20))
                                        .foregroundStyle((ARGBColor(hex: draft.theme == .night ? style.textColorNight : style.textColor) ?? ARGBColor(0xFF000000)).color)
                                        .frame(width: 48, height: 48)
                                        .background { ReaderBackgroundView(settings: previewSettings(style)).clipShape(Circle()) }
                                        .overlay(Circle().strokeBorder(index == store.selected ? Color.accentColor : .clear, lineWidth: 2))
                                }
                                .accessibilityLabel(style.name.isEmpty ? "预设 \(index)" : style.name)
                                .accessibilityIdentifier("reader.style.\(index)")
                                .accessibilityValue(previewSettings(style).backgroundValue)
                                .simultaneousGesture(LongPressGesture().onEnded { _ in
                                    enqueue { try await store.select(index); await adoptStyle(); customizing = true }
                                })
                            }
                            Button {
                                enqueue(operation: "新建阅读样式") { try await store.createStyle(); await adoptStyle(); customizing = true }
                            } label: {
                                Image(systemName: "plus").frame(width: 48, height: 48).background(.thinMaterial, in: Circle())
                            }.accessibilityLabel("新建样式").accessibilityIdentifier("reader.style.add")
                        }.padding(.horizontal, 6).padding(.vertical, 2)
                    }
                    Button("恢复预设布局") {
                        enqueue(operation: "恢复预设布局") { try await store.restorePresetLayout(); await adoptStyle() }
                    }
                }.padding(16)
            }
            .legadoNavigationTitle("阅读界面")
            .toolbar { Button("完成") { dismiss() } }
            .navigationDestination(isPresented: $customizing) { customization }
        }
        .presentationDetents([.height(470), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(470)))
        .onChange(of: chineseConverterType) { _, _ in enqueue { render(draft) } }
        .alert("阅读样式", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { error = nil }
        } message: { Text(error?.displayText ?? "") }
        .fileImporter(isPresented: $importing, allowedContentTypes: importingImage ? [.image] : [.json, .zip]) { result in
            enqueue(operation: importingImage ? "导入背景图片" : "导入阅读样式", sourceFile: (try? result.get())?.lastPathComponent) {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                if importingImage {
                    try await installBackground(data)
                } else { try await store.importStyles(data); await adoptStyle() }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            enqueue(operation: "导入相册背景") {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                try await installBackground(data)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .zip, defaultFilename: "readConfig") { result in
            if case .failure(let failure) = result { error = failure.presentation(operation: "导出阅读样式", sourceFile: "readConfig.zip") }
        }
    }

    private var backgroundColor: Binding<Color> {
        Binding(get: { color(backgroundPath).wrappedValue }, set: { value in
            mutate {
                $0.configuration[keyPath: backgroundPath] = Self.hex(value)
                $0.configuration[keyPath: backgroundTypePath] = 0
            }
        })
    }

    private func previewSettings(_ style: ReadBookConfig) -> ReaderSettings {
        var settings = draft; settings.configuration = style; return settings
    }

    private var backgroundImages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PhotosPicker("从相册选择", selection: $selectedPhoto, matching: .images)
                    Button("从文件选择") { importingImage = true; importing = true }
                }.buttonStyle(.bordered)
                Text("内置图库").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 12) {
                    ForEach(ReaderBackgroundResources.names, id: \.self) { name in
                        Button {
                            mutate {
                                $0.configuration[keyPath: backgroundPath] = name
                                $0.configuration[keyPath: backgroundTypePath] = 1
                            }
                        } label: {
                            VStack {
                                let preview = builtinSettings(name)
                                ReaderBackgroundView(settings: preview).frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(draft.backgroundType == 1 && draft.backgroundValue == name ? Color.accentColor : .clear, lineWidth: 3))
                                Text((name as NSString).deletingPathExtension).font(.caption).lineLimit(1)
                            }
                        }.accessibilityIdentifier("reader.background." + name)
                    }
                }
            }.padding()
        }.legadoNavigationTitle("背景图片")
    }

    private func builtinSettings(_ name: String) -> ReaderSettings {
        var settings = draft
        settings.configuration[keyPath: backgroundTypePath] = 1
        settings.configuration[keyPath: backgroundPath] = name
        settings.configuration.bgAlpha = 100
        return settings
    }

    private func installBackground(_ data: Data) async throws {
        guard data.count <= 30 * 1024 * 1024, let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let folder = URL.applicationSupportDirectory.appendingPathComponent("Legado/bg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
        var updated = draft
        updated.configuration[keyPath: backgroundPath] = name
        updated.configuration[keyPath: backgroundTypePath] = 2
        draft = updated
        try await store.update(updated.configuration); render(updated)
    }

    private var margins: some View {
        Form {
            Toggle("左右边距联动", isOn: $linkedMargins)
            marginGroup("页眉", top: \.headerPaddingTop, bottom: \.headerPaddingBottom,
                        left: \.headerPaddingLeft, right: \.headerPaddingRight, line: \.showHeaderLine)
            marginGroup("正文", top: \.paddingTop, bottom: \.paddingBottom, left: \.paddingLeft, right: \.paddingRight)
            marginGroup("页脚", top: \.footerPaddingTop, bottom: \.footerPaddingBottom,
                        left: \.footerPaddingLeft, right: \.footerPaddingRight, line: \.showFooterLine)
        }.legadoNavigationTitle("边距")
    }

    private func marginGroup(_ title: String, top: WritableKeyPath<ReadBookConfig, Int>, bottom: WritableKeyPath<ReadBookConfig, Int>,
                             left: WritableKeyPath<ReadBookConfig, Int>, right: WritableKeyPath<ReadBookConfig, Int>,
                             line: WritableKeyPath<ReadBookConfig, Bool>? = nil) -> some View {
        Section(title) {
            slider("上", value: number(top), range: 0...400, step: 1)
            slider("下", value: number(bottom), range: 0...400, step: 1)
            slider("左", value: marginBinding(left, partner: right), range: 0...100, step: 1)
            slider("右", value: marginBinding(right, partner: left), range: 0...100, step: 1)
            if let line { Toggle("显示分隔线", isOn: config(line)) }
        }
    }

    private var information: some View {
        Form {
            Section("状态栏") {
                Toggle("深色状态栏图标", isOn: config(draft.isEInk ? \.darkStatusIconEInk : draft.theme == .night ? \.darkStatusIconNight : \.darkStatusIcon))
            }
            Section("页眉") {
                tipPicker("左", \.tipHeaderLeft, template: \.tipHeaderLeftTemplate, name: "页眉左")
                tipPicker("中", \.tipHeaderMiddle, template: \.tipHeaderMiddleTemplate, name: "页眉中")
                tipPicker("右", \.tipHeaderRight, template: \.tipHeaderRightTemplate, name: "页眉右")
                Picker("显示", selection: config(\.headerMode)) {
                    Text("隐藏状态栏时显示").tag(0); Text("显示").tag(1); Text("隐藏").tag(2)
                }
            }
            Section("页脚") {
                tipPicker("左", \.tipFooterLeft, template: \.tipFooterLeftTemplate, name: "页脚左")
                tipPicker("中", \.tipFooterMiddle, template: \.tipFooterMiddleTemplate, name: "页脚中")
                tipPicker("右", \.tipFooterRight, template: \.tipFooterRightTemplate, name: "页脚右")
                Picker("显示", selection: config(\.footerMode)) { Text("显示").tag(0); Text("隐藏").tag(1) }
            }
            Section("信息文字") {
                slider("字号", value: number(\.tipTextSize), range: 5...50, step: 1)
                ColorPicker("颜色", selection: integerColor(\.tipColor))
                Button("跟随正文颜色") { config(\.tipColor).wrappedValue = 0 }
                ColorPicker("分隔线颜色", selection: integerColor(\.tipDividerColor))
                Button("跟随信息颜色") { config(\.tipDividerColor).wrappedValue = -1 }
            }
            Section("章节标题") {
                Picker("位置", selection: config(\.titleMode)) {
                    Text("左").tag(0); Text("中").tag(1); Text("右").tag(3); Text("隐藏").tag(2)
                }
                slider("字号偏移", value: number(\.titleSize), range: -8...48, step: 1)
                slider("行高偏移 (%)", value: number(\.titleLineSpacingExtra), range: -20...30, step: 1)
                NavigationLink("字体") { FontPicker(selection: config(\.titleFont)) }
                Picker("字重", selection: config(\.titleBold)) {
                    Text("跟随正文").tag(-1); Text("正常").tag(0); Text("粗体").tag(1); Text("细体").tag(2)
                }
                ColorPicker("颜色", selection: integerColor(\.titleColor))
                Button("跟随正文颜色") { config(\.titleColor).wrappedValue = 0 }
                Toggle("章节序号单独一行", isOn: config(\.splitChapterTitle))
                slider("序号字号偏移", value: number(\.titleNumberSize), range: -8...48, step: 1)
                ColorPicker("序号颜色", selection: integerColor(\.titleNumberColor))
                slider("序号下间距", value: number(\.titleNumberSpacing), range: 0...400, step: 1)
                slider("上间距", value: number(\.titleTopSpacing), range: 0...400, step: 1)
                slider("下间距", value: number(\.titleBottomSpacing), range: 0...400, step: 1)
            }
        }.legadoNavigationTitle("信息与标题")
    }

    private var underline: some View {
        Form {
            Picker("线型", selection: config(\.underlineMode)) {
                ForEach(Array(["关闭", "实线", "虚线", "点线", "双线", "波浪线", "双虚线"].enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }.accessibilityIdentifier("reader.underline.mode")
            Toggle("正文下划线", isOn: config(\.underlineBodyEnabled))
            Toggle("标题下划线", isOn: config(\.underlineTitleEnabled))
            Toggle("自定义下划线颜色", isOn: config(\.underlineColorSet))
            if draft.configuration.underlineColorSet { ColorPicker("下划线颜色", selection: integerColor(\.underlineColor)) }
            slider("线宽", value: config(\.underlineWidth), range: 0...10, step: 0.5)
            slider("距基线", value: config(\.underlineDistance), range: 0...30, step: 1)
        }.legadoNavigationTitle("下划线")
    }

    private var customization: some View {
        Form {
            TextField("样式名", text: config(\.name))
            ColorPicker("文字颜色", selection: color(textColorPath))
            ColorPicker("背景颜色", selection: backgroundColor)
            ColorPicker("强调颜色", selection: color(accentPath))
            NavigationLink("背景图片") { backgroundImages }
            slider("背景透明度", value: number(\.bgAlpha), range: 0...100, step: 1)
            Button("导入样式") { importingImage = false; importing = true }
            Button("导出样式") { enqueue { document = ReaderStyleDocument(data: try store.exportSelected()); exporting = true } }
            Button("删除样式", role: .destructive) {
                enqueue { try await store.deleteSelected(); await adoptStyle(); customizing = false }
            }.disabled(store.styles.count <= 5)
        }.legadoNavigationTitle("自定义样式")
    }

    private var textColorPath: WritableKeyPath<ReadBookConfig, String> {
        draft.isEInk ? \.textColorEInk : draft.theme == .night ? \.textColorNight : \.textColor
    }
    private var backgroundPath: WritableKeyPath<ReadBookConfig, String> {
        draft.isEInk ? \.bgStrEInk : draft.theme == .night ? \.bgStrNight : \.bgStr
    }
    private var backgroundTypePath: WritableKeyPath<ReadBookConfig, Int> {
        draft.isEInk ? \.bgTypeEInk : draft.theme == .night ? \.bgTypeNight : \.bgType
    }
    private var accentPath: WritableKeyPath<ReadBookConfig, String> {
        draft.isEInk ? \.textAccentColorEInk : draft.theme == .night ? \.textAccentColorNight : \.textAccentColor
    }

    private func tipPicker(_ title: String, _ path: WritableKeyPath<ReadBookConfig, Int>,
                           template: WritableKeyPath<ReadBookConfig, String?>, name: String) -> some View {
        let text = Binding(get: { draft.configuration[keyPath: template] ?? ReaderInfo.templates[draft.configuration[keyPath: path]] ?? "" },
            set: { value in mutate { $0.configuration[keyPath: template] = value } })
        return NavigationLink {
            ReaderTemplateEditor(name: name, initial: text.wrappedValue, preset: draft.configuration[keyPath: path]) { templateText, code in
                mutate { $0.configuration[keyPath: template] = templateText; $0.configuration[keyPath: path] = code }
            }
        } label: {
            HStack { Text(title); Spacer(); Text(text.wrappedValue.isEmpty ? "无" : text.wrappedValue).foregroundStyle(.secondary).lineLimit(1) }
        }.accessibilityIdentifier("reader.template." + name)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, divisor: Double = 1) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 14)).frame(width: 88, alignment: .leading)
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
            Text(value.wrappedValue / divisor, format: .number.precision(.fractionLength(divisor == 1 ? 0 : 1)))
                .font(.system(size: 13).monospacedDigit()).frame(minWidth: 30, alignment: .trailing)
        }
    }

    private func config<T>(_ path: WritableKeyPath<ReadBookConfig, T>) -> Binding<T> {
        Binding(get: { draft.configuration[keyPath: path] }, set: { value in mutate { $0.configuration[keyPath: path] = value } })
    }
    private func setting<T>(_ path: WritableKeyPath<ReaderSettings, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: path] }, set: { value in mutate { $0[keyPath: path] = value } })
    }
    private func number(_ path: WritableKeyPath<ReadBookConfig, Int>) -> Binding<Double> {
        Binding(get: { Double(draft.configuration[keyPath: path]) }, set: { config(path).wrappedValue = Int($0.rounded()) })
    }
    private func marginBinding(_ path: WritableKeyPath<ReadBookConfig, Int>, partner: WritableKeyPath<ReadBookConfig, Int>) -> Binding<Double> {
        Binding(get: { Double(draft.configuration[keyPath: path]) }, set: { value in
            mutate { settings in
                settings.configuration[keyPath: path] = Int(value)
                if linkedMargins { settings.configuration[keyPath: partner] = Int(value) }
            }
        })
    }
    private func color(_ path: WritableKeyPath<ReadBookConfig, String>) -> Binding<Color> {
        Binding(get: { (ARGBColor(hex: draft.configuration[keyPath: path]) ?? ARGBColor(0xFF000000)).color },
                set: { config(path).wrappedValue = Self.hex($0) })
    }
    private func integerColor(_ path: WritableKeyPath<ReadBookConfig, Int>) -> Binding<Color> {
        Binding(get: { ARGBColor(UInt32(truncatingIfNeeded: draft.configuration[keyPath: path])).color }, set: { value in
            let hex = Self.hex(value)
            let raw = UInt32(hex.dropFirst(), radix: 16) ?? 0
            config(path).wrappedValue = Int(Int32(bitPattern: raw))
        })
    }
    private static func hex(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X%02X", Int(alpha * 255), Int(red * 255), Int(green * 255), Int(blue * 255))
    }
    private func mutate(_ change: (inout ReaderSettings) -> Void) {
        var updated = draft; change(&updated); updated = updated.normalized; draft = updated
        let settings = updated
        enqueue { try await store.update(settings.configuration); settings.save(); render(settings) }
    }
    private func adoptStyle() async {
        var settings = draft; settings.configuration = store.current; draft = settings
        render(settings)
    }
    private func render(_ settings: ReaderSettings) {
        rendering?.cancel()
        rendering = Task { await apply(settings) }
    }
    private func enqueue(operation: String = "保存阅读样式", sourceFile: String? = nil, _ action: @escaping @MainActor () async throws -> Void) {
        let previous = work
        work = Task {
            await previous?.value
            do { try await action() } catch { self.error = error.presentation(operation: operation, subject: draft.configuration.name, sourceFile: sourceFile) }
        }
    }
}

struct ReaderStyleDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct ReaderTemplateEditor: View {
    let name: String
    let save: (String, Int) -> Void
    @State private var text: String
    @State private var preset: Int
    @Environment(\.dismiss) private var dismiss

    init(name: String, initial: String, preset: Int, save: @escaping (String, Int) -> Void) {
        self.name = name; self.save = save; _text = State(initialValue: initial); _preset = State(initialValue: preset)
    }

    var body: some View {
        Form {
            Section("自定义模板") {
                TextEditor(text: $text).frame(minHeight: 110).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("reader.template.editor")
                Button("清空模板") { text = "" }
                Text("支持下方占位符；清空模板可隐藏此位置。").font(.caption).foregroundStyle(.secondary)
            }
            Section("追加占位符") {
                ForEach(["{书名}", "{章节}", "{时间}", "{电量}", "{电量图标}", "{电量图标数值}", "{页码}", "{总页数}", "{阅读进度}", "{章节序号}", "{章节总数}"], id: \.self) { token in
                    Button(token) { text += token }
                }
            }
            Section("预设") {
                Picker("选择预设", selection: $preset) {
                    ForEach(ReaderInfo.choices, id: \.0) { Text($0.1).tag($0.0) }
                }.onChange(of: preset) { _, value in text = ReaderInfo.templates[value] ?? "" }
                Button("恢复所选预设") { text = ReaderInfo.templates[preset] ?? "" }
            }
        }.legadoNavigationTitle(name + "模板")
            .toolbar { Button("保存模板") { save(text, preset); dismiss() } }
    }
}
