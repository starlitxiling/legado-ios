import Foundation

public struct StrResponse: Sendable {
    public let raw: HttpResponse
    public let body: String
    public var url: String { raw.finalURL.absoluteString }
    public var code: Int { raw.status }
    public var headers: [String: String] { raw.headers }
    public var isSuccessful: Bool { (200..<300).contains(code) }

    public init(raw: HttpResponse, charset: String? = nil) throws {
        self.raw = raw
        body = try ResponseDecoder.decode(raw.body, headers: raw.headers, charset: charset)
    }
}
