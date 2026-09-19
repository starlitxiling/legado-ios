import Foundation
import Network

public struct HttpProxy: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Kind: String, Sendable { case http, socks4, socks5 }
    public enum ConfigurationError: Error, Equatable { case invalidProxy, unsupportedSocks4Authentication }
    public let kind: Kind
    public let host: String
    public let port: Int
    public let username: String?
    public let password: String?

    public init(_ input: String) throws {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacy = try NSRegularExpression(pattern: #"^(http|socks4|socks5)://(.+):(\d+)@([^@\s]+)@(.+)$"#, options: .caseInsensitive)
        if let match = legacy.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
            let text = input as NSString
            try self.init(scheme: text.substring(with: match.range(at: 1)), host: text.substring(with: match.range(at: 2)),
                port: Int(text.substring(with: match.range(at: 3))), username: text.substring(with: match.range(at: 4)),
                password: text.substring(with: match.range(at: 5)))
            return
        }
        guard !input.contains(where: { $0.isWhitespace || $0.isNewline }),
              let components = URLComponents(string: input), let scheme = components.scheme,
              let host = components.host, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              input.filter({ $0 == "@" }).count <= 1 else { throw ConfigurationError.invalidProxy }
        if components.user != nil && components.password == nil { throw ConfigurationError.invalidProxy }
        try self.init(scheme: scheme, host: host, port: components.port,
            username: components.user, password: components.password)
    }

    private init(scheme: String, host rawHost: String, port: Int?, username: String?, password: String?) throws {
        guard let kind = Kind(rawValue: scheme.lowercased()), let port, (1...65535).contains(port) else {
            throw ConfigurationError.invalidProxy
        }
        var host = rawHost
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        guard !host.isEmpty, !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0)
            || CharacterSet.controlCharacters.contains($0) || "/@?#[]%".unicodeScalars.contains($0) }) else {
            throw ConfigurationError.invalidProxy
        }
        if host.contains(":") {
            guard (try? UrlOptions.parseDnsIpAddresses(host)) != nil else { throw ConfigurationError.invalidProxy }
        } else {
            guard let encoded = URL(string: "http://" + host)?.host, !encoded.isEmpty else { throw ConfigurationError.invalidProxy }
            host = encoded
        }
        if let username {
            guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let password,
                  !username.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !password.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw ConfigurationError.invalidProxy
            }
            if kind == .socks4 { throw ConfigurationError.unsupportedSocks4Authentication }
            if kind == .socks5 && (!(1...255).contains(username.utf8.count) || !(1...255).contains(password.utf8.count)) {
                throw ConfigurationError.invalidProxy
            }
        }
        self.kind = kind; self.host = host; self.port = port
        self.username = username; self.password = password
    }

    public var description: String { kind.rawValue + "://" + (host.contains(":") ? "[" + host + "]" : host) + ":" + String(port) }
    public var debugDescription: String { description }

    func apply(to configuration: URLSessionConfiguration) {
        configuration.connectionProxyDictionary = dictionary
        if kind == .socks5 {
            var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: .init(host), port: .init(rawValue: UInt16(port))!))
            proxy.allowFailover = false
            if let username, let password { proxy.applyCredential(username: username, password: password) }
            configuration.proxyConfigurations = [proxy]
        }
    }

    public var dictionary: [String: Any] {
        if kind == .http {
            return ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                    "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port]
        }
        var result: [String: Any] = ["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port,
            "kCFStreamPropertySOCKSVersion": kind == .socks4 ? "kCFStreamSocketSOCKSVersion4" : "kCFStreamSocketSOCKSVersion5"]
        if let username, let password {
            result["kCFStreamPropertySOCKSUser"] = username
            result["kCFStreamPropertySOCKSPassword"] = password
        }
        return result
    }
}
