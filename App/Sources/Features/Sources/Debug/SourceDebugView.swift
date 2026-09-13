import SwiftUI
import LegadoCore

struct SourceDebugView: View {
    @State private var model: SourceDebugModel

    init(source: BookSource, client: any HttpClient) {
        _model = State(initialValue: SourceDebugModel(source: source, client: client))
    }

    var body: some View {
        @Bindable var model = model
        VStack {
            TextField("关键词、详情 URL、++目录 URL 或 --正文 URL", text: $model.key)
                .textInputAutocapitalization(.never).autocorrectionDisabled().padding()
            HStack {
                Button("开始调试") { model.start() }.disabled(model.isRunning || model.key.isEmpty)
                Button("停止") { model.stop() }.disabled(!model.isRunning)
            }
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.message).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.state == -1 ? Color.red : Color.primary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding()
            }
        }
        .navigationTitle("书源调试")
        .onDisappear { model.stop() }
    }
}
