import XCTest
import SwiftUI
import UIKit
@testable import Legado

@MainActor
final class ReaderScrollContainerTests: XCTestCase {
    func testDisabledContainerReflowsAndKeepsExternalSeek() {
        func value(height: Double, location: Int, enabled: Bool) -> ScrollPageContainer {
            ScrollPageContainer(pages: (0..<3).map { ReaderScrollPage(id: $0, height: height, content: AnyView(Text("Page \($0)"))) },
                location: location, progress: 0, enabled: enabled, select: { _ in })
        }
        let initial = value(height: 100, location: 1, enabled: true)
        let coordinator = ScrollPageContainer.Coordinator(initial)
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 50))
        scroll.contentSize = CGSize(width: 300, height: 2000)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        scroll.addSubview(host.view)
        coordinator.scroll = scroll; coordinator.host = host
        coordinator.update(initial)
        XCTAssertEqual(scroll.contentOffset.y, 100, accuracy: 0.1)
        coordinator.update(value(height: 200, location: 2, enabled: false))
        XCTAssertEqual(host.sizeThatFits(in: CGSize(width: 300, height: 2000)).height, 600, accuracy: 0.1)
        XCTAssertEqual(scroll.contentOffset.y, 400, accuracy: 0.1)
        coordinator.update(value(height: 200, location: 2, enabled: true))
        XCTAssertEqual(scroll.contentOffset.y, 400, accuracy: 0.1)
    }
}
