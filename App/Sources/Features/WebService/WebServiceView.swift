import SwiftUI

struct WebServiceView: View {
    @Bindable var model: WebServiceController

    var body: some View {
        Form {
            Section("局域网 HTTP 服务") {
                TextField("端口（默认 1122）", text: $model.portText)
                    .keyboardType(.numberPad).disabled(model.isRunning || model.isStarting)
                if model.isRunning || model.isStarting {
                    Button("停止服务", role: .destructive) { model.stop() }
                } else {
                    Button("启动服务") { model.start() }
                }
                ForEach(model.addresses, id: \.self) { address in
                    Text(address).textSelection(.enabled)
                }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent("书源访问令牌") { Text(model.accessToken).textSelection(.enabled) }
                Button("重置访问令牌") { model.resetToken() }
                Text("在同一局域网的浏览器打开上方地址。服务提供书架、书源与阅读接口；进入后台自动停止。请仅在可信局域网启用。")
                Text("WebSocket 书源调试与搜索暂未提供。")
            }
        }
        .navigationTitle("Web 服务")
    }
}
