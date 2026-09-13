import SwiftUI
import LegadoCore

struct DownloadCenterView: View {
    let model: DownloadCenterModel

    var body: some View {
        List {
            if model.progress.isEmpty { Text("暂无下载任务") }
            ForEach(Array(Set(model.progress.map(\.bookURL))).sorted(), id: \.self) { url in
                let items = model.progress.filter { $0.bookURL == url }
                Section(model.bookNames[url] ?? "书籍下载") {
                    ProgressView(value: Double(items.filter { $0.state == .completed }.count), total: Double(items.count))
                    HStack {
                        Button("暂停") { Task { await model.queue.pause(bookURL: url) } }
                        Button("继续") { Task { await model.queue.resume(bookURL: url) } }
                        Button("重试失败") { Task { await model.queue.retry(bookURL: url) } }
                        Button("取消", role: .destructive) { Task { await model.queue.cancel(bookURL: url) } }
                    }.buttonStyle(.borderless)
                    ForEach(items) { item in
                        VStack(alignment: .leading) {
                            Text("第 \(item.chapterIndex + 1) 章 · \(stateName(item.state)) · 已尝试 \(item.attempts) 次")
                            if let error = item.error { Text(error).font(.caption).foregroundStyle(.red) }
                        }
                    }
                }
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("下载中心")
        .task { await model.poll() }
    }

    private func stateName(_ state: CacheBook.State) -> String {
        switch state {
        case .queued: return "等待"
        case .running: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

struct BookCacheExportView: View {
    let book: BookRow
    let model: DownloadCenterModel
    @State private var start = 1
    @State private var end: Int
    @State private var useReplace = true
    @State private var epub = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var busy = false

    init(book: BookRow, model: DownloadCenterModel) {
        self.book = book; self.model = model
        _end = State(initialValue: max(1, book.totalChapterNum))
    }

    var body: some View {
        Form {
            Section("章节范围（从 1 开始）") {
                Stepper("起始：\(start)", value: $start, in: 1...max(1, book.totalChapterNum))
                Stepper("结束：\(end)", value: $end, in: 1...max(1, book.totalChapterNum))
            }
            Button("缓存所选范围") {
                Task { await model.download([book], range: (start - 1)...(end - 1)) }
            }.disabled(!valid)
            Button("缓存整本") { Task { await model.download([book]) } }.disabled(book.totalChapterNum == 0)
            NavigationLink("查看下载进度") { DownloadCenterView(model: model) }
            Section("导出") {
                Toggle("应用替换规则", isOn: $useReplace)
                Toggle("EPUB 格式", isOn: $epub)
                Button(busy ? "正在导出" : "生成导出文件") {
                    busy = true; exportURL = nil; errorMessage = nil
                    Task {
                        defer { busy = false }
                        do { exportURL = try await model.export(book, range: (start - 1)...(end - 1), epub: epub, useReplace: useReplace) }
                        catch { errorMessage = error.localizedDescription }
                    }
                }.disabled(busy || !valid)
                if let exportURL { ShareLink("分享导出文件", item: exportURL) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("缓存与导出")
    }

    private var valid: Bool { book.totalChapterNum > 0 && start <= end }
}
