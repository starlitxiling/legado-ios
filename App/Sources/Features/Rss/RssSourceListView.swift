import SwiftUI
import LegadoCore

struct RssSourceListView: View {
    let container: AppContainer
    @State private var model: RssSourceListModel
    @State private var editing: RssSource?
    @State private var importing = false
    @State private var importText = ""
    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: RssSourceListModel(repository: RssRepository(database: container.database), client: container.httpClient))
    }
    var body: some View {
        List {
            Picker("分组", selection: $model.selectedGroup) {
                ForEach(model.groups, id: \.self) { Text($0).tag($0) }
            }
            ForEach(model.visibleSources, id: \.sourceUrl) { source in
                NavigationLink {
                    if source.singleUrl {
                        RssReadView(article: RssArticle(origin: source.sourceUrl, link: source.columns.first?.url ?? source.sourceUrl, title: source.sourceName), source: source, repository: model.repository, client: model.client)
                    } else if case let .startHTML(html) = RssSourceDestination(source: source) {
                        RssReadView(article: RssArticle(origin: source.sourceUrl, link: source.sourceUrl, title: source.sourceName), source: source, repository: model.repository, client: model.client, startHTML: html)
                    } else {
                        RssArticlesView(source: source, repository: model.repository, client: model.client)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(source.sourceName.isEmpty ? source.sourceUrl : source.sourceName)
                        Text(source.sourceGroup ?? source.sourceUrl).font(.caption).foregroundStyle(.secondary)
                        if !source.enabled { Text("已停用").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .disabled(!source.enabled)
                .swipeActions(edge: .leading) {
                    Button("编辑") { editing = source }.tint(.blue)
                    Button(source.enabled ? "停用" : "启用") {
                        Task { var value = source; value.enabled.toggle(); do { try await model.save(value) } catch { model.error = String(describing: error) } }
                    }.tint(.orange)
                }
                .swipeActions {
                    Button("删除", role: .destructive) { Task { await model.delete(source) } }
                }
            }
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("RSS")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink { RssFavoritesView(repository: model.repository, client: model.client) } label: { Image(systemName: "star") }
                Menu {
                    Button("添加订阅源") { editing = RssSource() }
                    Button("导入 JSON 或链接") { importing = true }
                } label: { Image(systemName: "plus") }
            }
        }
        .task { await model.reload() }
        .refreshable { await model.reload() }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let editing {
                NavigationStack {
                    RssSourceEditView(source: editing) { value in
                        try await model.save(value, replacing: editing.sourceUrl.isEmpty ? nil : editing.sourceUrl)
                    }
                }
            }
        }
        .sheet(isPresented: $importing) {
            NavigationStack {
                Form {
                    TextEditor(text: $importText).frame(minHeight: 240)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("导入 RSS 源")
                .toolbar {
                    Button("取消") { importing = false }
                    Button(model.importing ? "导入中" : "导入") {
                        Task { await model.importText(importText); if model.error == nil { importing = false; importText = "" } }
                    }.disabled(model.importing)
                }
            }
        }
    }
}
