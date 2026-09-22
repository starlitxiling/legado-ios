#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

struct ErrorPresentationGallery: View {
    @State private var error = URLError(.timedOut).presentation(operation: "加载正文", subject: "测试书籍", actions: [.retry])
    @State private var retryCount = 0
    @State private var showsImporter = false

    var body: some View {
        NavigationStack {
            VStack {
                Text("重试次数：\(retryCount)")
                Button("选择文件") { showsImporter = true }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("错误提示")
                .errorBanner(error, dismiss: { error = nil }) { action in
                    if action == .retry { retryCount += 1; error = nil }
                }
                .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
                    if case .failure(let failure) = result { error = failure.presentation(operation: "选择文件") }
                }
        }
    }
}
#endif
