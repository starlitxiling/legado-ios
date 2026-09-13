import Foundation
import Network
import Darwin
import LegadoCore

@MainActor
final class NWWebServiceTransport: WebServiceTransport {
    private var listener: NWListener?
    private var monitor: NWPathMonitor?
    private var connections: [UUID: NWConnection] = [:]
    private var requests: [UUID: Task<Void, Never>] = [:]
    private var deadlines: [UUID: DispatchWorkItem] = [:]

    func start(port: UInt16, router: HttpRouter, state: @escaping (WebServiceState) -> Void) throws {
        stop()
        guard let port = NWEndpoint.Port(rawValue: port) else { throw WebHttpError.malformed }
        let listener = try NWListener(using: .tcp, on: port)
        self.listener = listener
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self, weak listener] _ in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                state(.networkChanged)
            }
        }
        monitor.start(queue: .main)
        listener.stateUpdateHandler = { [weak self, weak listener] value in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                switch value {
                case .ready: state(.ready)
                case .failed(let error): state(.failed(error.localizedDescription))
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener, self.connections.count < 16 else { connection.cancel(); return }
                let id = UUID()
                self.connections[id] = connection
                let deadline = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.close(id) }
                }
                self.deadlines[id] = deadline
                DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: deadline)
                connection.start(queue: .main)
                self.receive(connection, id: id, bytes: Data(), router: router)
            }
        }
        listener.start(queue: .main)
    }

    private func receive(_ connection: NWConnection, id: UUID, bytes: Data, router: HttpRouter) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, self.connections[id] != nil else { return }
                var bytes = bytes
                if let data { bytes.append(data) }
                do {
                    if let request = try WebHttpRequest.parse(bytes) {
                        self.requests[id] = Task { [weak self] in
                            let response = await router.handle(request)
                            guard let self, !Task.isCancelled, self.connections[id] != nil else { return }
                            self.send(response, to: connection, id: id)
                        }
                    } else if complete || error != nil { self.close(id) }
                    else { self.receive(connection, id: id, bytes: bytes, router: router) }
                } catch {
                    let status = (error as? WebHttpError) == .tooLarge ? 413 : 400
                    self.send(WebHttpResponse(status: status, contentType: "text/plain", body: Data("Invalid HTTP request".utf8)), to: connection, id: id)
                }
            }
        }
    }

    private func send(_ response: WebHttpResponse, to connection: NWConnection, id: UUID) {
        connection.send(content: response.encoded(), completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        deadlines.removeValue(forKey: id)?.cancel()
        requests.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)?.cancel()
    }

    func stop() {
        monitor?.cancel(); monitor = nil
        listener?.cancel(); listener = nil
        for id in Array(connections.keys) { close(id) }
    }

    static func localAddresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses = Set<String>()
        var cursor = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.insert(String(cString: host))
            }
        }
        return addresses.sorted()
    }
}

extension WebServiceController {
    static func live(database: AppDatabase, client: any HttpClient) -> WebServiceController {
        let stored = UserDefaults.standard.integer(forKey: "webPort")
        let token = WebServiceToken(try? KeychainStore().read(account: "jsSourceApiToken"))
        return WebServiceController(router: HttpRouter(api: WebApi(database: database, client: client,
                                                                   cacheDirectory: .applicationSupportDirectory,
                                                                   bookshelfSort: { UserDefaults.standard.integer(forKey: "bookshelfSort") },
                                                                   booksDirectory: URL.documentsDirectory.appendingPathComponent("Books")),
                                                       token: { UserDefaults.standard.string(forKey: "jsSourceApiToken") ?? token.value },
                                                       tokenRequired: { UserDefaults.standard.object(forKey: "jsSourceApiTokenRequired") as? Bool ?? true }),
                                    transport: NWWebServiceTransport(), port: (1...65535).contains(stored) ? stored : 1122,
                                    addresses: { NWWebServiceTransport.localAddresses() },
                                    savePort: { UserDefaults.standard.set($0, forKey: "webPort") },
                                    token: token, saveToken: {
                                        try KeychainStore().write($0, account: "jsSourceApiToken")
                                        UserDefaults.standard.set($0, forKey: "jsSourceApiToken")
                                    })
    }
}
