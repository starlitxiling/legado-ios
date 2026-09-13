import SwiftUI
import WebKit

struct VerificationCodeView: View {
    let webView: WKWebView
    @Bindable var model: BrowserModel
    let onComplete: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack {
                BrowserPage(webView: webView)
                TextField("验证码", text: $model.verificationCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .padding()
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("输入验证码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { if let code = model.submittedCode { onComplete(code) } }
                        .disabled(model.submittedCode == nil || model.isCompleting)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
