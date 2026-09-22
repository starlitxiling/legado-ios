import SwiftUI
import LegadoCore

struct GroupEditView: View {
    let repository: BookGroupRepository
    var initialGroupID: Int64? = nil
    @State private var expanded = Set<Int64>()
    @State private var groups: [BookGroupRow] = []
    @State private var name = ""
    @State private var userError: UserFacingError?
    private var errorMessage: String? { userError?.displayText }

    var body: some View {
        ScrollViewReader { scroll in
            List {
                Section("新建分组") {
                    TextField("分组名称", text: $name)
                    Button("添加") {
                        Task { await perform("新建分组") { _ = try await repository.createGroup(name: name); name = "" } }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("分组设置") {
                    ForEach($groups, id: \.groupId) { $group in
                        DisclosureGroup(group.groupName.isEmpty ? "分组 \(group.groupId)" : group.groupName,
                            isExpanded: Binding(get: { expanded.contains(group.groupId) }, set: { value in
                                if value { expanded.insert(group.groupId) } else { expanded.remove(group.groupId) }
                            })) {
                            TextField("名称", text: $group.groupName)
                            TextField("封面 URL", text: Binding(get: { group.cover ?? "" }, set: { group.cover = $0.isEmpty ? nil : $0 }))
                            Toggle("显示分组", isOn: $group.show)
                            Toggle("更新章节", isOn: $group.enableRefresh)
                            Toggle("仅更新已读书籍", isOn: $group.onlyUpdateRead)
                            Picker("排序", selection: $group.bookSort) {
                                Text("跟随书架").tag(-1)
                                Text("最近阅读").tag(0)
                                Text("最近更新").tag(1)
                                Text("书名").tag(2)
                                Text("手动顺序").tag(3)
                                Text("综合排序").tag(4)
                                Text("作者").tag(5)
                            }
                            Button("保存设置") { let value = group; Task { await perform("保存分组设置") { try await repository.update(value) } } }
                            if group.groupId > 0 {
                                Button("删除分组", role: .destructive) { let id = group.groupId; Task { await perform("删除分组") { try await repository.removeCustomGroup(id) } } }
                            }
                        }.id(group.groupId)
                    }
                    .onMove { offsets, destination in
                        groups.move(fromOffsets: offsets, toOffset: destination)
                        let ids = groups.map(\.groupId)
                        Task { await perform("调整分组顺序") { try await repository.reorder(ids) } }
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .legadoNavigationTitle("编辑分组")
            .toolbar { EditButton() }
            .task {
                await perform("加载分组") { try await repository.ensureBuiltinGroups() }
                if let initialGroupID { expanded.insert(initialGroupID); scroll.scrollTo(initialGroupID, anchor: .top) }
            }
        }
    }

    @MainActor
    private func perform(_ operation: String, _ action: () async throws -> Void) async {
        do { try await action(); groups = try await repository.list(); userError = nil }
        catch { userError = error.presentation(operation: operation, subject: name.isEmpty ? nil : name) }
    }
}
