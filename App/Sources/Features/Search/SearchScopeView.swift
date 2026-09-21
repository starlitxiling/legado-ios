import SwiftUI
import LegadoCore

struct SearchScopeView: View {
    let sources: [BookSourceSummary]
    let onSelect: (SearchScope) -> Void
    @State private var sourceMode: Bool
    @State private var selectedGroups: Set<String>
    @State private var selectedSource: String?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    init(sources: [BookSourceSummary], scope: SearchScope, onSelect: @escaping (SearchScope) -> Void) {
        self.sources = sources; self.onSelect = onSelect
        _sourceMode = State(initialValue: scope.sourceURL != nil)
        _selectedGroups = State(initialValue: Set(scope.groups))
        _selectedSource = State(initialValue: scope.sourceURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("搜索范围", selection: $sourceMode) { Text("分组").tag(false); Text("书源").tag(true) }
                    .pickerStyle(.segmented).padding().accessibilityIdentifier("search.scope.mode")
                if sourceMode { CapsuleSearchField(text: $query, prompt: "筛选书源").padding(.horizontal) }
                List {
                    if sourceMode {
                        ForEach(sources.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }) { source in
                            Button { selectedSource = source.id } label: {
                                Label(source.name, systemImage: selectedSource == source.id ? "largecircle.fill.circle" : "circle")
                            }.accessibilityIdentifier("search.scope.source." + source.id)
                        }
                    } else {
                        ForEach(Array(Set(sources.filter(\.enabled).flatMap(\.groups))).sorted(), id: \.self) { group in
                            Button {
                                if !selectedGroups.insert(group).inserted { selectedGroups.remove(group) }
                            } label: { Label(group, systemImage: selectedGroups.contains(group) ? "checkmark.square.fill" : "square") }
                            .accessibilityIdentifier("search.scope.group." + group)
                        }
                    }
                }
                HStack {
                    Button("全部书源") { onSelect(.init()); dismiss() }
                    Spacer()
                    Button("取消") { dismiss() }
                    Button("确定") {
                        if sourceMode, let source = sources.first(where: { $0.id == selectedSource }) { onSelect(.source(source)) }
                        else if sourceMode { onSelect(.init()) }
                        else { onSelect(.init(value: selectedGroups.sorted().joined(separator: ","))) }
                        dismiss()
                    }
                }.padding()
            }.legadoNavigationTitle("多分组 / 书源")
        }
    }
}
