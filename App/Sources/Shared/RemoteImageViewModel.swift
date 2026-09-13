import Foundation
import Observation

@Observable
@MainActor
final class RemoteImageViewModel {
    enum State: Equatable { case placeholder, loading, loaded(Data), failed }
    private(set) var state: State = .placeholder
    private var generation = 0

    func load(url: String?, operation: () async throws -> Data) async {
        generation += 1
        let request = generation
        guard let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .placeholder; return
        }
        state = .loading
        do {
            let data = try await operation()
            try Task.checkCancellation()
            guard request == generation else { return }
            state = data.isEmpty ? .failed : .loaded(data)
        } catch {
            guard request == generation else { return }
            state = error is CancellationError || (error as? URLError)?.code == .cancelled ? .placeholder : .failed
        }
    }
}
