import SwiftUI
import LegadoCore

struct SourceDebugView: View {
    @State private var focused = false
    @State private var model: SourceDebugModel

    init(source: BookSource, client: any HttpClient) {
        _model = State(initialValue: SourceDebugModel(source: source, client: client))
    }

    var body: some View {
        @Bindable var model = model
        VStack {
            if focused && !model.isRunning {
                VStack(alignment: .leading, spacing: 14) {
                    Text("书名：输入书名调试搜索")
                    Text("书籍 URL：https://example.com/book")
                    Text("目录 URL：++https://example.com/toc")
                    Text("正文 URL：--https://example.com/chapter")
                    Text("发现：输入 :: 加发现地址")
                }.font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            HStack {
                Button("开始调试") { focused = false; model.start() }.disabled(model.isRunning || model.key.isEmpty)
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
        .legadoNavigationTitle("书源调试")
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("书名、URL 或发现", text: $model.key, onEditingChanged: { focused = $0 })
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .padding(.horizontal, 12).frame(height: 30).inkSurface(Capsule(), material: .thinMaterial)
                    .onSubmit { focused = false; model.start() }
            }
        }
        .overlay { if model.isRunning { ProgressView().allowsHitTesting(false) } }
        .onDisappear { model.stop() }
    }
}
