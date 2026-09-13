import XCTest
import LegadoCore
@testable import WebServiceCheck

final class WebSocketSessionTests: XCTestCase {
    @MainActor
    func testPingBinaryAndRemoteClose() throws {
        var output: [WebSocketFrame] = []
        var decoder = WebSocketFrameDecoder(requireMask: false)
        var ended = 0
        let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in AsyncThrowingStream { $0.finish() } })
        let session = WebSocketSession(path: "/searchBook", routes: routes, send: { bytes, done in
            output += try! decoder.append(bytes); done(true)
        }, end: { ended += 1 })
        session.receive(WebSocketFrame(opcode: .ping, payload: Data([1, 2])).encoded(mask: [0, 0, 0, 0]))
        XCTAssertEqual(output, [.init(opcode: .pong, payload: Data([1, 2]))])
        session.receive(WebSocketFrame.close(code: 1000, reason: "bye").encoded(mask: [0, 0, 0, 0]))
        XCTAssertEqual(output.last, .close(code: 1000, reason: "bye"))
        XCTAssertEqual(ended, 1)
        session.receive(WebSocketFrame(opcode: .ping).encoded(mask: [0, 0, 0, 0]))
        XCTAssertEqual(output.count, 2)
    }

    @MainActor
    func testFirstMessageOnlyAndCloseWaitsForPeer() async throws {
        var output: [WebSocketFrame] = []
        var decoder = WebSocketFrameDecoder(requireMask: false)
        var calls = 0, ended = 0
        let closing = expectation(description: "server close")
        let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in
            calls += 1
            return AsyncThrowingStream { $0.yield([]); $0.finish() }
        })
        let session = WebSocketSession(path: "/searchBook", routes: routes, send: { bytes, done in
            let frames = try! decoder.append(bytes); output += frames; done(true)
            if frames.contains(where: { $0.opcode == .close }) { closing.fulfill() }
        }, end: { ended += 1 })
        let request = WebSocketFrame(opcode: .binary, payload: Data(#"{"key":"book"}"#.utf8)).encoded(mask: [1, 2, 3, 4])
        session.receive(request + request)
        await fulfillment(of: [closing], timeout: 2)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(output, [.init(opcode: .text, payload: Data("[]".utf8)), .close(code: 1000, reason: "Search finish")])
        XCTAssertEqual(ended, 0)
        session.receive(WebSocketFrame.close(code: 1000, reason: "").encoded(mask: [0, 0, 0, 0]))
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testTimeoutAndProtocolError() {
        for timeout in [true, false] {
            var output: [WebSocketFrame] = []
            var decoder = WebSocketFrameDecoder(requireMask: false)
            let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in AsyncThrowingStream { $0.finish() } })
            let session = WebSocketSession(path: "/searchBook", routes: routes, send: { bytes, done in
                output += try! decoder.append(bytes); done(true)
            }, end: {})
            if timeout { session.authenticationTimedOut() }
            else { session.receive(Data([0x81, 0])) }
            XCTAssertEqual(output.first?.opcode, .close)
            XCTAssertEqual(output.first?.payload.prefix(2), Data(timeout ? [3, 240] : [3, 234]))
            session.stop()
        }
    }

    @MainActor
    func testStoppingCancelsDebugProducer() async {
        let started = expectation(description: "debug started")
        let cancelled = expectation(description: "debug cancelled")
        let routes = WebSocketRoutes(bookDebug: { _, _ in
            AsyncStream { continuation in
                continuation.onTermination = { _ in cancelled.fulfill() }
                started.fulfill()
            }
        }, rssDebug: { _ in nil }, search: { _ in AsyncThrowingStream { $0.finish() } })
        let session = WebSocketSession(path: "/bookSourceDebug", routes: routes, send: { _, done in done(true) }, end: {})
        session.receive(WebSocketFrame(opcode: .text, payload: Data(#"{"tag":"source","key":"book"}"#.utf8)).encoded(mask: [0, 0, 0, 0]))
        await fulfillment(of: [started], timeout: 2)
        session.stop()
        await fulfillment(of: [cancelled], timeout: 2)
    }

    @MainActor
    func testRemoteCloseWaitsForWriteCompletion() {
        var completion: ((Bool) -> Void)?
        var ended = 0, writes = 0
        let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in AsyncThrowingStream { $0.finish() } })
        let session = WebSocketSession(path: "/searchBook", routes: routes, send: { _, done in
            writes += 1; completion = done
        }, end: { ended += 1 })
        let close = WebSocketFrame.close(code: 1000, reason: "bye").encoded(mask: [0, 0, 0, 0])
        session.receive(close)
        session.receive(close)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(ended, 0)
        completion?(true)
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testReviewProtocolFailureStopsReceivingBeforeCloseWrite() {
        var completion: ((Bool) -> Void)?
        var writes: [Data] = [], ended = 0
        let routes = WebSocketRoutes(bookDebug: { _, _ in nil }, rssDebug: { _ in nil }, search: { _ in AsyncThrowingStream { $0.finish() } })
        let session = WebSocketSession(path: "/searchBook", routes: routes, send: { bytes, done in
            writes.append(bytes); completion = done
        }, end: { ended += 1 })
        session.receive(Data([0x81, 0]))
        XCTAssertFalse(session.shouldReceive)
        session.receive(WebSocketFrame.close(code: 1000, reason: "").encoded(mask: [0, 0, 0, 0]))
        XCTAssertEqual(writes, [WebSocketFrame.close(code: 1002, reason: "WebSocket frame error").encoded()])
        XCTAssertEqual(ended, 0)
        completion?(true)
        XCTAssertEqual(ended, 1)
    }

    func testReviewSavedSearchPreferences() {
        var values: [String: Any] = ["searchScope": "甲,乙", "threadCount": 3, "precisionSearch": true]
        let first = WebSocketSearchOptions.saved(read: { values[$0] })
        XCTAssertEqual(first.scope, "甲,乙")
        XCTAssertEqual(first.threadCount, 3)
        XCTAssertTrue(first.precisionSearch)
        values["searchScope"] = "单源::source"
        XCTAssertEqual(WebSocketSearchOptions.saved(read: { values[$0] }).scope, "单源::source")
        values.removeAll()
        let fallback = WebSocketSearchOptions.saved(read: { values[$0] })
        XCTAssertEqual(fallback.scope, "")
        XCTAssertEqual(fallback.threadCount, 32)
        XCTAssertFalse(fallback.precisionSearch)
    }
}
