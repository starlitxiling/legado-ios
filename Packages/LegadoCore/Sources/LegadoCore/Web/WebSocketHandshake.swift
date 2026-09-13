import Foundation
import CryptoKit

public enum WebSocketHandshake {
    public static func accept(key: String) -> String {
        Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
    }

    public static func requested(_ request: WebHttpRequest) -> Bool {
        request.headers["upgrade"]?.lowercased() == "websocket"
    }

    public static func authorized(_ request: WebHttpRequest, token: String?, required: Bool) -> Bool {
        let protocols = protocols(request)
        guard protocols.first == "legado" else { return false }
        if !required { return true }
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty,
              protocols.count == 2 else { return false }
        let encoded = Data(token.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let expected = Array(("legado.token." + encoded).utf8), actual = Array(protocols[1].utf8)
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public static func response(_ request: WebHttpRequest) throws -> Data {
        guard request.method == "GET", requested(request),
              request.headers["host"]?.trimmingCharacters(in: .whitespaces).isEmpty == false,
              request.headers["connection"]?.lowercased().split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).contains("upgrade") == true,
              request.headers["sec-websocket-version"] == "13", let key = request.headers["sec-websocket-key"],
              Data(base64Encoded: key)?.count == 16, request.body.isEmpty else { throw WebSocketError.protocolError }
        let selected = protocols(request).contains("legado") ? "Sec-WebSocket-Protocol: legado\r\n" : ""
        return Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept(key: key))\r\n\(selected)\r\n".utf8)
    }

    private static func protocols(_ request: WebHttpRequest) -> [String] {
        (request.headers["sec-websocket-protocol"] ?? "").split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
