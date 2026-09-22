import SwiftUI
import LegadoCore

struct ReaderReviewView: View {
    let model: ReaderViewModel
    @State private var paragraph = 1
    @State private var items: [ReaderReviewItem] = []
    @State private var errorMessage: UserFacingError?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                HStack { ReaderReviewIcon(settings: model.settings, count: items.count); Text("段评") }
                Stepper("第 \(paragraph) 段", value: $paragraph, in: 1...10000)
                if isLoading { ProgressView("正在加载段评") }
                if let errorMessage { Text(errorMessage.displayText).foregroundStyle(.red) }
                if !isLoading && items.isEmpty && errorMessage == nil { Text("暂无段评") }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.caption).foregroundStyle(.secondary)
                        Text(item.content)
                    }
                }
            }
            .legadoNavigationTitle("段评")
            .toolbar { Button("完成") { dismiss() } }
            .task(id: paragraph) {
                isLoading = true; errorMessage = nil
                do {
                    let result = try await model.reviews(paragraph: paragraph)
                    try Task.checkCancellation()
                    items = result; isLoading = false
                } catch {
                    if !Task.isCancelled { errorMessage = error.presentation(operation: "加载段评", subject: "\(model.book?.name ?? "") · 第 \(paragraph) 段"); isLoading = false }
                }
            }
        }
    }
}
