import Foundation
import Observation
import LegadoCore

@Observable
@MainActor
final class CheckSourceViewModel {
    private let checker: SourceChecker
    var keyword = "我的"
    private(set) var results: [BookSourceCheckState] = []
    private(set) var completedCount = 0
    private(set) var isRunning = false
    private(set) var currentSource = ""
    private(set) var currentStep: SourceCheckStep?
    var errorMessage: String?

    init(checker: SourceChecker) { self.checker = checker }
    func run(sources: [BookSource]) async {
        guard !isRunning else { return }
        isRunning = true; completedCount = 0; results = []; errorMessage = nil
        defer { isRunning = false; currentStep = nil; currentSource = "" }
        do {
            for source in sources {
                try Task.checkCancellation()
                currentSource = source.bookSourceName ?? source.bookSourceUrl ?? ""
                currentStep = .search
                let result = try await checker.check(source: source, keyword: keyword) { step in
                    await MainActor.run { self.currentStep = step.step }
                }
                results.append(result); completedCount += 1
            }
        } catch is CancellationError { errorMessage = "校验已取消" }
        catch { errorMessage = error.localizedDescription }
    }
}
