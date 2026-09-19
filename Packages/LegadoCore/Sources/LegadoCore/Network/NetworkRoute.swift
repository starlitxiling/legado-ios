import Foundation

public enum NetworkRoutingError: Error, Equatable, LocalizedError {
    case invalidCustomHosts
    case invalidAddress(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCustomHosts: return "customHosts must be a JSON object mapping hosts to IP strings or arrays."
        case let .invalidAddress(host): return "Invalid IP address mapping for host: " + host
        }
    }
}

public struct CustomHosts: Sendable {
    public let addresses: [String: [String]]

    public init(_ json: String) throws {
        if json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addresses = [:]; return }
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)), let entries = object as? [String: Any] else {
            throw NetworkRoutingError.invalidCustomHosts
        }
        var addresses: [String: [String]] = [:]
        for (host, value) in entries {
            let values: String
            if let string = value as? String { values = string }
            else if let strings = value as? [String] { values = strings.joined(separator: ",") }
            else { throw NetworkRoutingError.invalidAddress(host) }
            guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
                  let parsed = try? UrlOptions.parseDnsIpAddresses(values) else { throw NetworkRoutingError.invalidAddress(host) }
            addresses[host.lowercased()] = parsed
        }
        self.addresses = addresses
    }
}

struct NetworkRoute {
    let logicalURL: URL
    let request: HttpRequest
    let tlsHost: String?
    let direct: Bool

    init(request: HttpRequest, addressIndex: Int = 0) throws {
        logicalURL = request.url
        guard request.proxy == nil, let host = request.url.host,
              let addresses = request.hostAddresses[host.lowercased()], !addresses.isEmpty else {
            self.request = request; tlsHost = nil; direct = false; return
        }
        guard addresses.indices.contains(addressIndex), var components = URLComponents(url: request.url, resolvingAgainstBaseURL: true),
              let normalized = try? UrlOptions.parseDnsIpAddresses(addresses[addressIndex]), normalized.count == 1 else {
            throw NetworkRoutingError.invalidAddress(host)
        }
        let address = normalized[0]
        components.host = address.contains(":") ? "[" + address + "]" : address
        guard let physicalURL = components.url else { throw NetworkRoutingError.invalidAddress(host) }
        var outgoing = request
        outgoing.url = physicalURL
        if outgoing.headers.httpHeader("Host") == nil {
            outgoing.headers["Host"] = host + (request.url.port.map { ":" + String($0) } ?? "")
        }
        self.request = outgoing
        tlsHost = request.url.scheme?.lowercased() == "https" ? host : nil
        direct = true
    }

    func logicalResponse(_ response: HttpResponse) -> HttpResponse {
        guard direct, response.finalURL.host == request.url.host else { return response }
        return HttpResponse(status: response.status, body: response.body, finalURL: logicalURL, headers: response.headers)
    }
}
