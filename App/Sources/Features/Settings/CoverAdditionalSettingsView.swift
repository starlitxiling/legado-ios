import SwiftUI
import LegadoCore

@MainActor struct CoverRuleSettingsView: View {
    @State private var model: CoverRuleSettingsModel
    init(database: AppDatabase) { _model = State(initialValue: CoverRuleSettingsModel(database: database)) }
    var body: some View {
        @Bindable var model = model
        Form {
            Text("searchUrl 使用 {{key}} 引用书名，coverRule 支持阅读规则语法。")
            TextEditor(text: $model.text).font(.system(.caption, design: .monospaced)).frame(minHeight: 280)
            Button("保存封面规则") { Task { await model.save() } }
            if let message = model.message { Text(message) }
        }.navigationTitle("封面规则").task { await model.load() }
    }
}

@MainActor struct ReadRecordCoversView: View {
    @Environment(AppContainer.self) private var container
    @State private var records: [ReadRecordRow] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error) }
            ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                HStack {
                    RemoteImage(url: record.coverUrl, origin: nil, book: book(record), isReadRecord: true)
                        .frame(width: 48, height: 72)
                    VStack(alignment: .leading) {
                        Text(record.bookName)
                        Text(record.author).font(.caption).foregroundStyle(.secondary)
                        Text(record.lastChapterTitle ?? "").font(.caption)
                    }
                }
            }
        }.navigationTitle("阅读记录").task {
            do { records = try await container.readProgress.all().sorted { $0.lastRead > $1.lastRead } }
            catch { self.error = error.localizedDescription }
        }
    }
    private func book(_ record: ReadRecordRow) -> Book {
        var book = Book(now: 0); book.name = record.bookName; book.author = record.author
        return book
    }
}
