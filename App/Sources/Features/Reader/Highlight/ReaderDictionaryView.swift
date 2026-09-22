import SwiftUI
import WebKit
import SafariServices
import LegadoCore

struct ReaderDictionaryView: View {
    let word: String
    let database: AppDatabase
    let client: any HttpClient
    @State private var rules: [DictRule] = []
    @State private var selected = ""
    @State private var html = ""
    @State private var running = false
    @State private var error: UserFacingError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !rules.isEmpty {
                    Picker("词典", selection: $selected) {
                        ForEach(rules) { rule in Text(rule.name).tag(rule.name) }
                    }.pickerStyle(.menu).padding(8)
                }
                if running { ProgressView("正在查询").padding() }
                if let error { Text(error.displayText).foregroundStyle(.red).padding() }
                if rules.isEmpty && !running { Text("没有启用的字典规则，请在我的页面添加或启用。").padding() }
                ReaderDictionaryResult(html: html)
            }.legadoNavigationTitle(word)
                .toolbar { Button("完成") { dismiss() } }
                .task {
                    do {
                        rules = try await DictRuleRepository(database: database).list().filter(\.enabled)
                        selected = rules.first?.name ?? ""
                    } catch { self.error = error.presentation(operation: "读取字典规则", subject: word) }
                }
                .task(id: selected) {
                    guard let rule = rules.first(where: { $0.name == selected }) else { return }
                    running = true; error = nil; html = ""
                    let word = word, client = client
                    let request = Task.detached { try await rule.search(word: word, client: client) }
                    do {
                        let result = try await withTaskCancellationHandler { try await request.value } onCancel: { request.cancel() }
                        try Task.checkCancellation()
                        html = result; running = false
                    } catch is CancellationError { }
                    catch { self.error = error.presentation(operation: "字典查询", subject: rule.name + " · " + word); running = false }
                }
        }
    }
}

private struct ReaderDictionaryResult: UIViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        let body = html.contains("<") ? html : "<pre>" + html.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") + "</pre>"
        view.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font:18px -apple-system;padding:12px;overflow-wrap:anywhere}pre{white-space:pre-wrap}img{max-width:100%}</style>" + body, baseURL: nil)
    }
    final class Coordinator { var html: String? }
}

struct ReaderSelectionBrowser: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    private var url: URL? {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { return url }
        var components = URLComponents(string: "https://www.baidu.com/s")
        components?.queryItems = [URLQueryItem(name: "wd", value: text)]
        return components?.url
    }
    var body: some View {
        if let url { SafariPage(url: url).ignoresSafeArea() }
        else { Text("无法打开所选文本。").padding() }
    }
}

private struct SafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
