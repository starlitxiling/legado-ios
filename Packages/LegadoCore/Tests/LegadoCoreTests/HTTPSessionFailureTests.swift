import XCTest
@testable import LegadoCore

final class HTTPSessionFailureTests: XCTestCase {
    func testRejectedTLSChallengeProducesVisibleCertificateFailure() async throws {
        try await assertFailure(certificate: true, expected: .serverCertificateUntrusted)
    }

    func testInvalidatedSessionDoesNotProduceCancellation() async throws {
        try await assertFailure(certificate: false, expected: .networkConnectionLost)
    }

    private func assertFailure(certificate: Bool, expected: URLError.Code) async throws {
        let started = expectation(description: "Transfer registered")
        SilentProtocol.started = started
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SilentProtocol.self]
        let delegate = HTTPSessionDelegate(proxy: nil, tlsHost: "example.test")
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel(); SilentProtocol.started = nil }
        let transfer = BoundedTransfer(limit: 100, follow: false)
        let result = Task { try await transfer.send(URLRequest(url: URL(string: "https://example.test")!), session: session, delegate: delegate) }
        await fulfillment(of: [started], timeout: 2)
        let tasks = await session.allTasks
        let task = try XCTUnwrap(tasks.first)
        if certificate {
            let space = URLProtectionSpace(host: "example.test", port: 443, protocol: "https", realm: nil,
                authenticationMethod: NSURLAuthenticationMethodServerTrust)
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
                previousFailureCount: 0, failureResponse: nil, error: nil, sender: ChallengeSender())
            delegate.urlSession(session, task: task, didReceive: challenge) { disposition, _ in
                XCTAssertEqual(disposition, .cancelAuthenticationChallenge)
            }
        } else {
            delegate.urlSession(session, didBecomeInvalidWithError: nil)
        }
        do { _ = try await result.value; XCTFail("Expected transfer failure") }
        catch { XCTAssertEqual((error as? URLError)?.code, expected) }
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

private final class SilentProtocol: URLProtocol {
    static var started: XCTestExpectation?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.started?.fulfill() }
    override func stopLoading() {}
}
