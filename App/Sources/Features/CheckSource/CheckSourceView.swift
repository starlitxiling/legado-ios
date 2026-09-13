import SwiftUI
import LegadoCore

struct CheckSourceView: View {
    let sources: [BookSource]
    @State private var model: CheckSourceViewModel
    @State private var task: Task<Void, Never>?
    init(sources: [BookSource], checker: SourceChecker) {
        self.sources = sources
        _model = State(initialValue: CheckSourceViewModel(checker: checker))
    }
    var body: some View {
        @Bindable var model = model
        List {
            TextField("校验关键词", text: $model.keyword).disabled(model.isRunning)
            if model.isRunning {
                ProgressView(value: Double(model.completedCount), total: Double(max(1, sources.count)))
                Text(model.currentSource + " · " + (model.currentStep?.title ?? "准备"))
                Button("取消") { task?.cancel() }
            } else {
                Button("校验 \(sources.count) 个书源") { task = Task { await model.run(sources: sources) } }
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            ForEach(model.results) { result in
                Section(result.sourceName) {
                    ForEach(result.steps, id: \.step) { step in
                        VStack(alignment: .leading) {
                            Text("\(step.step.title)：\(step.elapsedMilliseconds) ms")
                                .foregroundStyle(step.error == nil ? Color.green : Color.red)
                            if let error = step.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                        }
                    }
                }
            }
        }
        .navigationTitle("书源校验")
        .onDisappear { task?.cancel() }
    }
}
