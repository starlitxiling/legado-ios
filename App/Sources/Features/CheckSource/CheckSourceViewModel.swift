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
    var userError: UserFacingError?
    var errorMessage: String? { userError?.displayText }

    init(checker: SourceChecker) { self.checker = checker }
    func run(sources: [BookSource]) async {
        guard !isRunning else { return }
        isRunning = true; completedCount = 0; results = []; userError = nil
        defer { isRunning = false; currentStep = nil; currentSource = "" }
        do {
            for source in sources {
                try Task.checkCancellation()
                currentSource = source.bookSourceName ?? source.bookSourceUrl ?? ""
                currentStep = .search
                let result = try await checker.check(source: source, keyword: keyword, describeError: { error in
                    error.presentation(operation: "校验书源", subject: [source.bookSourceName, source.bookSourceUrl].compactMap { $0 }.joined(separator: " · "))?.displayText ?? "校验已取消"
                }) { step in
                    await MainActor.run { self.currentStep = step.step }
                }
                results.append(result); completedCount += 1
            }
        } catch is CancellationError { userError = nil }
        catch { userError = error.presentation(operation: "校验书源", subject: currentSource) }
    }
}
