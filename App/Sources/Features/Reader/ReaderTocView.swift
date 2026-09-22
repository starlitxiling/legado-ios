import SwiftUI
import UniformTypeIdentifiers
import LegadoCore

struct ReaderTocView: View {
    let model: ReaderViewModel
    let database: AppDatabase
    @State private var tab = 0
    @State private var query = ""
    @State private var entries: [ReaderTocEntry] = []
    @State private var outline: [ReaderTocEntry] = []
    @State private var collapsed = Set<String>()
    @State private var error: UserFacingError?
    @State private var parsing = false
    @State private var log = false
    @State private var progress: (Int, Int)?
    @State private var countTask: Task<Void, Never>?
    @State private var exporting = false
    @State private var exportType = UTType.json
    @State private var document = ReaderDirectoryDocument(data: Data())
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    private var localExtension: String { model.readerBook.flatMap(LocalBook.fileURL)?.pathExtension.lowercased() ?? "" }
    private var currentEntries: [ReaderTocEntry] { tab == 2 ? outline : entries }
    private var visible: [ReaderTocEntry] {
        ReaderTocPresentation.visible(currentEntries, collapsed: collapsed, query: query,
            reversed: model.readerBook?.readConfig?.reverseTocDisplay ?? false)
    }
    private var parents: Set<String> { Set(currentEntries.compactMap(\.parent)) }

    var body: some View {
        NavigationStack {
            Group {
                if tab == 1 { bookmarkList }
                else { chapterList }
            }
            .searchable(text: $query, prompt: tab == 1 ? "搜索书签" : "搜索目录")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Picker("目录标签", selection: $tab) {
                        Text("目录").tag(0); Text("书签").tag(1)
                        if localExtension == "pdf" { Text("大纲").tag(2) }
                    }.pickerStyle(.segmented).frame(width: localExtension == "pdf" ? 220 : 160)
                }
                ToolbarItem(placement: .topBarTrailing) { directoryMenu }
            }
            .safeAreaInset(edge: .bottom) {
                if let progress {
                    HStack {
                        ProgressView(value: Double(progress.0), total: Double(max(1, progress.1)))
                        Text("\(progress.0)/\(progress.1)").font(.caption)
                        Button("停止") { countTask?.cancel() }
                    }.padding()
                } else {
                    Text("已缓存 \(model.cachedChapterIndices.count) / \(model.chapters.count) 章").font(.caption).foregroundStyle(.secondary).padding(8)
                }
            }
        }
        .task(id: model.book?.readConfig) { await load() }
        .onDisappear { countTask?.cancel() }
        .sheet(isPresented: $parsing, onDismiss: { Task { await load() } }) { ReaderTextParsingView(model: model, database: database) }
        .sheet(isPresented: $log) { NavigationStack { AppLogView() } }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType,
                      defaultFilename: "bookmark-\(model.book?.name ?? "book")") { result in
            if case .failure(let failure) = result { error = failure.presentation(operation: "导出书签", subject: model.book?.name) }
        }
        .alert("目录操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error?.displayText ?? "") }
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List {
                if visible.isEmpty { Text(tab == 2 ? "此 PDF 没有大纲" : "没有匹配的章节").foregroundStyle(.secondary) }
                ForEach(visible) { item in
                    HStack(spacing: 8) {
                        if parents.contains(item.id) {
                            Button {
                                if !collapsed.insert(item.id).inserted { collapsed.remove(item.id) }
                            } label: { Image(systemName: collapsed.contains(item.id) ? "chevron.right" : "chevron.down").frame(width: 24, height: 32) }
                                .buttonStyle(.borderless).accessibilityLabel("折叠或展开 \(item.title)")
                        }
                        Button {
                            guard item.chapterIndex != nil else {
                                if !collapsed.insert(item.id).inserted { collapsed.remove(item.id) }; return
                            }
                            Task { await model.openTocEntry(item); dismiss() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.system(size: 15)).multilineTextAlignment(.leading)
                                    if let count = model.chapters.first(where: { $0.index == item.chapterIndex })?.wordCount, !count.isEmpty {
                                        Text("\(count) 字").font(.caption)
                                    }
                                }
                                Spacer(minLength: 0)
                                if item.chapterIndex == model.chapterIndex { Image(systemName: "checkmark") }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.isLoading).accessibilityIdentifier("reader.toc.\(item.id)")
                    }
                    .padding(.leading, CGFloat(min(12, max(0, item.depth))) * 16)
                    .foregroundStyle(item.chapterIndex == model.chapterIndex ? colors.accent :
                        (item.chapterIndex.map { model.cachedChapterIndices.contains($0) } == true ? colors.textPrimary : colors.textSecondary))
                    .id(item.id)
                }
            }.listStyle(.plain)
                .onChange(of: entries) { _, _ in locate(proxy) }
                .onChange(of: tab) { _, _ in locate(proxy) }
                .onAppear { locate(proxy) }
        }
    }

    private var bookmarkList: some View {
        List {
            Button("添加当前位置书签", systemImage: "bookmark") { Task { await model.addBookmark() } }
            ForEach(model.bookmarks.filter { query.isEmpty || ($0.chapterName + $0.bookText + $0.content).localizedCaseInsensitiveContains(query) }, id: \.time) { item in
                Button { Task { await model.openBookmark(item); dismiss() } } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.chapterName)
                        Text(item.bookText).font(.caption).lineLimit(3)
                        if !item.content.isEmpty { Text(item.content).font(.caption).foregroundStyle(.secondary) }
                    }
                }.swipeActions { Button("删除", role: .destructive) { Task { await model.deleteBookmark(item) } } }
            }
        }.listStyle(.plain)
    }

    private var directoryMenu: some View {
        Menu {
            if localExtension == "txt" {
                Button("TXT 目录规则 / 设置编码") { parsing = true }
                Toggle("拆分超长章节", isOn: Binding(get: { model.readerBook?.readConfig?.splitLongChapter ?? true }, set: { enabled in
                    Task { await model.updateReadConfig { $0.splitLongChapter = enabled }; await model.rebuildLocalDirectory(); await load() }
                }))
            }
            Toggle("反转目录", isOn: Binding(get: { model.readerBook?.readConfig?.reverseTocDisplay ?? false }, set: { enabled in
                Task { await model.updateReadConfig { $0.reverseTocDisplay = enabled } }
            }))
            Toggle("目录展开", isOn: Binding(get: { model.readerBook?.readConfig?.tocExpanded ?? true }, set: { enabled in
                collapsed = enabled ? [] : parents
                Task { await model.updateReadConfig { $0.tocExpanded = enabled } }
            }))
            Toggle("使用替换", isOn: Binding(get: { model.readerBook?.useReplaceRule(defaultEnabled: model.replaceEnableDefault()) ?? true }, set: { enabled in
                Task { await model.updateReadConfig { $0.useReplaceRule = enabled } }
            }))
            Button("加载字数") { countWords() }.disabled(countTask != nil)
            Button("导出书签") { export(markdown: false) }
            Button("导出 md") { export(markdown: true) }
            Button("日志") { log = true }
        } label: { Image(systemName: "ellipsis") }.accessibilityLabel("目录菜单")
    }
    private func locate(_ proxy: ScrollViewProxy) {
        guard let entry = currentEntries.first(where: { $0.chapterIndex == model.chapterIndex }) else { return }
        collapsed.subtract(ReaderTocPresentation.ancestors(of: entry.id, in: currentEntries))
        proxy.scrollTo(entry.id, anchor: .center)
    }
    private func load() async {
        do {
            let result = try await model.directoryPresentation()
            try Task.checkCancellation()
            let pdf = localExtension == "pdf"
            entries = ReaderTocPresentation.entries(chapters: result.chapters, nodes: pdf ? [] : result.nodes)
            outline = pdf ? ReaderTocPresentation.entries(chapters: result.chapters, nodes: result.nodes, includeUnlisted: false) : []
            collapsed = model.readerBook?.readConfig?.tocExpanded == false ? Set((entries + outline).compactMap(\.parent)) : []
            if let current = entries.first(where: { $0.chapterIndex == model.chapterIndex }) {
                collapsed.subtract(ReaderTocPresentation.ancestors(of: current.id, in: entries))
            }
            await model.waitForPrefetch(); await model.refreshCacheStatus()
        } catch is CancellationError { }
        catch { self.error = error.presentation(operation: "读取目录", subject: model.book?.name) }
    }
    private func countWords() {
        guard countTask == nil else { return }
        countTask = Task {
            defer { countTask = nil; progress = nil }
            do { try await model.loadChapterWordCounts { progress = ($0, $1) } }
            catch is CancellationError { }
            catch { self.error = error.presentation(operation: "统计章节字数", subject: model.book?.name) }
        }
    }
    private func export(markdown: Bool) {
        do {
            if markdown {
                document = ReaderDirectoryDocument(data: Data(ReaderTocPresentation.bookmarkMarkdown(name: model.book?.name ?? "", author: model.book?.author ?? "", bookmarks: model.bookmarks).utf8))
                exportType = UTType(filenameExtension: "md") ?? .plainText
            } else { document = ReaderDirectoryDocument(data: try JSONEncoder().encode(model.bookmarks)); exportType = .json }
            exporting = true
        } catch { self.error = error.presentation(operation: "生成书签文件", subject: model.book?.name) }
    }
}

struct ReaderDirectoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ReaderTextParsingView: View {
    let model: ReaderViewModel
    let database: AppDatabase
    @State private var rules: [TxtTocRule] = []
    @State private var charset = "UTF-8"
    @State private var busy = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("设置编码") {
                    TextField("字符编码", text: $charset).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("常用编码", selection: $charset) {
                        ForEach(Array(Set(["UTF-8", "UTF-16LE", "UTF-16BE", "GB18030", "GBK", "BIG5", "Shift_JIS", charset])).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Button("应用编码并重建目录") { run { await model.rebuildLocalDirectory(charset: charset) } }
                }
                Section("TXT 目录规则") {
                    Button("自动识别") { run { await model.rebuildLocalDirectory(automatic: true) } }
                    ForEach(rules, id: \.id) { rule in
                        Button(rule.name) { run { await model.rebuildLocalDirectory(rule: rule) } }
                    }
                }
                if busy { ProgressView("重建目录") }
            }.disabled(busy).legadoNavigationTitle("TXT 目录规则")
                .toolbar { Button("完成") { dismiss() }.disabled(busy) }
        }
        .interactiveDismissDisabled(busy)
        .task {
            charset = model.readerBook?.charset ?? "UTF-8"
            do { rules = try await TxtTocRuleRepository(database: database).list(); if rules.isEmpty { rules = TxtTocRule.builtIn } }
            catch { self.error = error.presentation(operation: "读取目录规则", subject: model.book?.name) }
        }
        .alert("目录重建失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error?.displayText ?? "") }
    }
    private func run(_ operation: @escaping () async -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            await operation(); busy = false
            if let message = model.userError { error = message } else { dismiss() }
        }
    }
}
