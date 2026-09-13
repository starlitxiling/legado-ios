import XCTest
@testable import BrowserCheck

final class BrowserCheckTests: XCTestCase {
    func testResourceRegexBacktracksAcrossSharedPrefixAlternatives() {
        XCTAssertTrue(WebViewResourceMatcher.matches("https://a/b", pattern: "https://a|https://a/b"))
        XCTAssertFalse(WebViewResourceMatcher.matches("https://a/b/c", pattern: "https://a|https://a/b"))
    }

    func testVerificationRequiresNonblankCode() {
        let model = BrowserModel()
        model.verificationCode = " \n "
        XCTAssertNil(model.submittedCode)
        model.verificationCode = "  aB12 \n"
        XCTAssertEqual(model.submittedCode, "aB12")
    }

    func testResourceRegexUsesFullMatch() {
        XCTAssertTrue(WebViewResourceMatcher.matches("https://example.com/video.mp4", pattern: "https://.*[.]mp4"))
        XCTAssertFalse(WebViewResourceMatcher.matches("https://example.com/video.mp4?x=1", pattern: "https://.*[.]mp4"))
        XCTAssertFalse(WebViewResourceMatcher.matches("https://example.com/video.mp4", pattern: "mp4"))
        XCTAssertFalse(WebViewResourceMatcher.matches("anything", pattern: "["))
        XCTAssertFalse(WebViewResourceMatcher.matches("anything", pattern: nil))
    }
}
