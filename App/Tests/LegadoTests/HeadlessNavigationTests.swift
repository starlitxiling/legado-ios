import XCTest
import WebKit
import LegadoCore
@testable import Legado

@MainActor
final class HeadlessNavigationTests: XCTestCase {
    func testInterruptedNavigationKeepsRequestAliveForNextNavigation() async {
        for provisional in [false, true] {
            let session = HeadlessWebViewSession(request: HeadlessWebViewRequest())
            let webView = WKWebView(frame: .zero)
            do {
                let _: StrResponse = try await withCheckedThrowingContinuation { continuation in
                    session.continuation = continuation
                    let interrupted = NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue)
                    if provisional { session.webView(webView, didFailProvisionalNavigation: nil, withError: interrupted) }
                    else { session.webView(webView, didFail: nil, withError: interrupted) }
                    XCTAssertFalse(session.completed)
                    session.webView(webView, didFail: nil, withError: URLError(.timedOut))
                }
                XCTFail("Expected subsequent navigation failure")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .timedOut)
                XCTAssertNotNil(error.presentation(operation: "Load page"))
            }
            XCTAssertTrue(session.completed)
        }
    }

    func testNonURLDomainWithCancelledCodeIsNotIgnored() async {
        let session = HeadlessWebViewSession(request: HeadlessWebViewRequest())
        let webView = WKWebView(frame: .zero)
        do {
            let _: StrResponse = try await withCheckedThrowingContinuation { continuation in
                session.continuation = continuation
                session.webView(webView, didFail: nil, withError: NSError(domain: "Fixture", code: -999))
            }
            XCTFail("Expected navigation failure")
        } catch { XCTAssertEqual((error as NSError).domain, "Fixture") }
        XCTAssertTrue(session.completed)
    }
}
