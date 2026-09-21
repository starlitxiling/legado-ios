import SwiftUI
import LegadoCore
import GRDB

struct ReaderMemoView: View {
    let bookURL: String
    let database: AppDatabase
    @State private var memo = BookMemo()
    @State private var draft = ""
    @State private var editing = false
    @State private var saving = false
    @State private var loaded = false
    @State private var error: String?
    @State private var confirmsClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if editing { TextEditor(text: $draft).padding(12).disabled(saving) }
                else {
                    ScrollView {
                        Text(memo.content.isEmpty ? "暂无备忘录" : .init(memo.content))
                            .frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
                    }
                }
                if memo.updatedAt > 0 {
                    Text(Date(timeIntervalSince1970: Double(memo.updatedAt) / 1000), style: .date).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(editing ? "取消" : "清空", role: .destructive) {
                        if editing { editing = false } else { confirmsClear = true }
                    }.disabled(!editing && memo.content.isEmpty)
                    Spacer()
                    Button(editing ? "保存" : "编辑") {
                        if editing { Task { await save(draft) } }
                        else { draft = memo.content; editing = true }
                    }
                }.padding().disabled(!loaded || saving)
            }
            .legadoNavigationTitle("书籍备忘录")
            .toolbar { Button("完成") { dismiss() }.disabled(editing || saving) }
        }
        .presentationDetents([.medium, .large]).interactiveDismissDisabled(editing || saving)
        .task {
            do {
                memo = try await database.write { db in try BookMemo.fetchOne(db, key: bookURL) } ?? BookMemo()
                memo.bookUrl = bookURL; loaded = true
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("清空备忘录？", isPresented: $confirmsClear) {
            Button("清空", role: .destructive) { Task { await save("") } }
        }
        .alert("备忘录操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func save(_ content: String) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        var value = memo
        value.content = content; value.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            memo = try await BookMemoRepository(database: database).upsert(value)
            editing = false
        } catch { self.error = error.localizedDescription }
    }
}
