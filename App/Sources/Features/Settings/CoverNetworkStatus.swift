import Foundation
import Network
import Observation

@Observable @MainActor
final class CoverNetworkStatus {
    static let shared = CoverNetworkStatus()
    private(set) var isWifi = false
    private let monitor = NWPathMonitor()
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            Task { @MainActor in self?.isWifi = wifi }
        }
        monitor.start(queue: DispatchQueue(label: "Legado.coverNetwork"))
    }
}
