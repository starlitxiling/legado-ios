import SwiftUI

struct ReaderSearchView: View {
    let model: ReaderViewModel
    @State private var query = ""
    @State private var matches: [ReaderSearchMatch] = []
    @State private var task: Task<Void, Never>?
    @State private var running = false
    @State private var progress = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                HStack {
                    TextField("搜索正文", text: $query).submitLabel(.search).onSubmit { search() }
                    Button(running ? "停止" : "搜索") { if running { task?.cancel(); running = false } else { search() } }
                        .disabled(query.isEmpty)
                }
                if !progress.isEmpty { Text(progress).font(.caption) }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(matches) { match in
                    Button {
                        task?.cancel(); dismiss(); Task { await model.openSearchResult(match) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(match.title).font(.headline)
                            Text(match.snippet).font(.body).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
                if matches.count >= 1000 { Text("已显示前 1000 个结果，请缩小搜索范围。") }
            }.legadoNavigationTitle("全文搜索")
                .toolbar { Button("关闭") { dismiss() } }
        }.onDisappear { task?.cancel() }
    }
    private func search() {
        guard !query.isEmpty else { return }
        task?.cancel(); running = true; matches = []; error = nil
        let text = query
        task = Task {
            do {
                let values = try await model.searchText(text) { done, total in progress = "已搜索 \(done) / \(total) 章" }
                try Task.checkCancellation(); matches = values; running = false
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; running = false }
        }
    }
}

struct ReaderContentEditor: View {
    let model: ReaderViewModel
    @State private var text = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).padding(12)
                .legadoNavigationTitle("编辑本章内容")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saving = true
                            Task { await model.editContent(text); saving = false; if model.errorMessage == nil { dismiss() } }
                        }.disabled(saving)
                    }
                }
                .onAppear { text = model.rawContent }
        }
    }
}

struct ReaderReplacePreviewView: View {
    let model: ReaderViewModel
    @State private var replaced = true
    var body: some View {
        NavigationStack {
            VStack {
                Picker("内容", selection: $replaced) { Text("处理后").tag(true); Text("原始内容").tag(false) }.pickerStyle(.segmented).padding()
                ScrollView { Text(replaced ? model.pagination?.text.string ?? "" : model.rawContent).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
            }.legadoNavigationTitle("替换预览")
        }
    }
}
