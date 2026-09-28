import XCTest
import SwiftUI
import UIKit
@testable import Legado

@MainActor
final class ReaderStatusAppearanceTests: XCTestCase {
    func testStatusControllerPreservesContentTraitsAndRestoresDelegation() {
        let content = UIViewController()
        content.overrideUserInterfaceStyle = .dark
        let controller = ReaderStatusBarController(content: content)
        controller.loadViewIfNeeded()
        XCTAssertTrue(content.parent === controller)
        controller.darkIcons = true
        XCTAssertEqual(controller.preferredStatusBarStyle, .darkContent)
        XCTAssertNil(controller.childForStatusBarStyle)
        XCTAssertEqual(content.overrideUserInterfaceStyle, .dark)
        controller.darkIcons = false
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(content.overrideUserInterfaceStyle, .dark)
        controller.darkIcons = nil
        XCTAssertTrue(controller.childForStatusBarStyle === content)
        XCTAssertTrue(controller.childForStatusBarHidden === content)
    }

    func testBridgeInstallsOneContainerPerWindow() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        let content = UIViewController()
        window.rootViewController = content
        window.isHidden = false
        defer { window.isHidden = true }
        let bridge = ReaderStatusBarBridge.BridgeView()
        bridge.darkIcons = true; bridge.interfaceStyle = .dark
        content.view.addSubview(bridge)
        bridge.apply()
        let controller = window.rootViewController as? ReaderStatusBarController
        XCTAssertNotNil(controller)
        XCTAssertTrue(controller?.content === content)
        bridge.darkIcons = false; bridge.apply()
        XCTAssertTrue(window.rootViewController === controller)
        XCTAssertEqual(controller?.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(controller?.overrideUserInterfaceStyle, .dark)
    }

    func testReaderStatusIconsDoNotOverrideApplicationScheme() {
        let dark = ThemePalette(primary: ARGBColor(0xFF000000), accent: ARGBColor(0xFFFFFFFF),
            background: ARGBColor(0xFF000000), bottomBackground: ARGBColor(0xFF000000), isNight: true, isEInk: false)
        let appearance = ReaderStatusAppearance(mode: .dark, palette: dark, darkIcons: true)
        XCTAssertEqual(appearance.colorScheme, .dark)
        XCTAssertEqual(appearance.darkStatusIcons, true)
        let light = ReaderStatusAppearance(mode: .light, palette: .defaultLight, darkIcons: false)
        XCTAssertEqual(light.colorScheme, .light)
        XCTAssertEqual(light.darkStatusIcons, false)
        XCTAssertNil(ReaderStatusAppearance(mode: .system, palette: dark, darkIcons: true).colorScheme)
    }
}
