import XCTest
import UIKit
@testable import Legado

final class ComponentIconTests: XCTestCase {
    func testEveryMappedSymbolExistsOnIOS() {
        for (name, symbol) in LegadoIcon.symbols {
            XCTAssertNotNil(UIImage(systemName: symbol), "\(name): \(symbol)")
        }
    }
}
