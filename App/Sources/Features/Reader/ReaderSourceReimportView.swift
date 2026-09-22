import SwiftUI
import LegadoCore

struct ReaderSourceReimportView: View {
    let sourceURL: String
    let repository: BookSourceRepository
    let completed: () async -> Void
    @State private var model: SourcesViewModel

    init(sourceURL: String, repository: BookSourceRepository, client: any ResponseLimitedHttpClient,
         completed: @escaping () async -> Void) {
        self.sourceURL = sourceURL; self.repository = repository; self.completed = completed
        let model = SourcesViewModel(repository: repository, httpClient: client)
        model.keepEnable = true
        model.useSourceReplacement = true
        _model = State(initialValue: model)
    }

    var body: some View {
        SourceImportSheet(title: "书源", entry: .url, preview: model.importPreview, isBusy: model.isBusy,
            errorMessage: model.errorMessage, prepareText: { await model.prepareImport(text: $0) },
            prepareURL: { await model.prepareImport(url: $0) }, confirm: {
                await model.confirmImport()
                guard model.errorMessage == nil, model.importPreview == nil else { return false }
                await completed(); return true
            }, cancel: { model.cancelImport() }, keepEnable: $model.keepEnable, sourceReplacement: $model.useSourceReplacement)
            .task {
                do {
                    guard let row = try await repository.get(bookSourceUrl: sourceURL) else { throw ReaderError.missingSource }
                    let source = try ReaderEntityBridge.decode(BookSource.self, row: row)
                    await model.prepareImport(text: String(decoding: try JSONEncoder().encode(source), as: UTF8.self))
                } catch { model.userError = error.presentation(operation: "重新导入书源", subject: sourceURL) }
            }
    }
}
