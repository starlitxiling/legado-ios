import SwiftUI
import LegadoCore

struct BookshelfRefreshReportView: View {
    let report: BookshelfRefresh.Report
    let container: AppContainer
    @State private var books: [String: BookRow] = [:]
    @State private var errorMessage: String?

    var body: some View {
        List {
            Text("已更新 \(report.updated.count) 本，\(report.failures.count) 本失败")
            ForEach(BookshelfRefresh.FailureKind.allCases, id: \.self) { kind in
                let failures = report.failures.filter { $0.kind == kind }
                if !failures.isEmpty {
                    Section(title(kind) + " (\(failures.count))") {
                        ForEach(failures, id: \.bookURL) { failure in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(books[failure.bookURL]?.name ?? failure.bookURL).font(.system(size: 16))
                                Text(failure.message).font(.system(size: 13)).foregroundStyle(.secondary)
                                if kind == .missingSource, let book = books[failure.bookURL] {
                                    NavigationLink("换源") { replacementSearch(book) }
                                        .accessibilityIdentifier("bookshelf.replaceSource." + book.bookUrl)
                                }
                            }
                        }
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .legadoNavigationTitle("更新结果")
        .task {
            do { books = Dictionary(uniqueKeysWithValues: try await container.bookshelf.all().map { ($0.bookUrl, $0) }) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func replacementSearch(_ book: BookRow) -> some View {
        let model = SearchViewModel(sources: container.bookSources, client: container.httpClient,
            keywords: SearchKeywordRepository(database: container.database), bookshelf: container.bookshelf, records: container.readProgress)
        model.query = book.name
        return SearchView(container: container, model: model)
    }

    private func title(_ kind: BookshelfRefresh.FailureKind) -> String {
        switch kind {
        case .missingSource: return "缺少书源"
        case .timeout: return "请求超时"
        case .parsing: return "解析失败"
        case .network: return "网络失败"
        case .other: return "其他失败"
        }
    }
}
