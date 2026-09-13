import Foundation
import Observation
import LegadoCore

@Observable @MainActor
final class SourceDebugModel {
    var key = ""
    private(set) var lines: [SourceDebugLog] = []
    private(set) var isRunning = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let debugger: SourceDebugger
    private let source: BookSource

    init(source: BookSource, client: any HttpClient) {
        self.source = source; debugger = SourceDebugger(client: client)
        key = source.ruleSearch?.checkKeyWord ?? ""
    }

    func start() {
        stop(); lines = []; isRunning = true
        let run = UUID(); generation = run
        let stream = debugger.logs(source: source, key: key)
        task = Task { [weak self] in
            for await line in stream {
                guard !Task.isCancelled, let self, self.generation == run else { break }
                self.lines.append(line)
                if UserDefaults.standard.bool(forKey: "recordLog") { NSLog("%@", line.message) }
            }
            guard let self, self.generation == run else { return }
            self.isRunning = false; self.task = nil
        }
    }

    func stop() { generation = UUID(); task?.cancel(); task = nil; isRunning = false }
}
