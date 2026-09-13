import XCTest
import LegadoCore
@testable import WebServiceCheck

@MainActor
final class WebServiceTests: XCTestCase {
    func testPortAndForegroundLifecycle() async throws {
        let transport = FakeTransport()
        let model = WebServiceController(router: HttpRouter(api: WebApi(database: try .inMemory())),
                                         transport: transport, port: 1122, addresses: { ["192.168.1.2"] }, savePort: { _ in })
        model.portText = "0"; model.start()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(transport.starts, 0)
        model.portText = "1234"; model.start()
        transport.state?(.ready)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.addresses, ["http://192.168.1.2:1234"])
        model.enterBackground()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(transport.stops, 1)
        XCTAssertTrue(model.message?.contains("后台") == true)
        model.start()
        XCTAssertEqual(transport.starts, 1)
        model.enterForeground(); model.start()
        XCTAssertEqual(transport.starts, 2)
    }

    func testReview7NetworkChangesRefreshAddresses() async throws {
        let transport = FakeTransport()
        var addresses = ["192.168.1.2"]
        let model = WebServiceController(router: HttpRouter(api: WebApi(database: try .inMemory())), transport: transport,
            addresses: { addresses }, savePort: { _ in })
        model.start(); transport.state?(.ready)
        addresses = ["192.168.2.3"]
        transport.state?(.networkChanged)
        XCTAssertEqual(model.addresses, ["http://192.168.2.3:1122"])
        model.stop(); transport.state?(.networkChanged)
        XCTAssertEqual(model.addresses, [])
    }

    func testLateReadyCannotRestartStoppedService() async throws {
        let transport = FakeTransport()
        let model = WebServiceController(router: HttpRouter(api: WebApi(database: try .inMemory())),
                                         transport: transport, port: 1122, addresses: { [] }, savePort: { _ in })
        model.start()
        let stale = transport.state
        model.stop(); stale?(.ready)
        XCTAssertFalse(model.isRunning)
    }
}

@MainActor
private final class FakeTransport: WebServiceTransport {
    var starts = 0
    var stops = 0
    var state: ((WebServiceState) -> Void)?
    func start(port: UInt16, router: HttpRouter, state: @escaping (WebServiceState) -> Void) throws {
        starts += 1; self.state = state
    }
    func stop() { stops += 1 }
}
