import Foundation
import MacBuddyCore

final class OverlayTests: CheckSuite {
    private let primary = CGRect(x: 0, y: 80, width: 1470, height: 840)
    func testPositionRoundTripsAndNegativeScreenOrigins() {
        let screens = [primary, CGRect(x: -1920, y: -300, width: 1920, height: 1040), CGRect(x: 1600, y: 900, width: 1200, height: 740)]
        for screen in screens {
            for x in [0.0, 0.3, 0.5, 1] {
                for y in [0.0, 0.25, 0.75, 1] {
                    let original = FloatingPosition(screenID: "external", horizontal: x, vertical: y)
                    let frame = OverlayGeometry.frame(for: original, size: OverlayGeometry.collapsedSize, within: screen)
                    expectTrue(screen.contains(frame))
                    let restored = OverlayGeometry.position(for: frame, screenID: "external", within: screen)
                    expectEqual(restored.horizontal, x, accuracy: 0.00001)
                    expectEqual(restored.vertical, y, accuracy: 0.00001)
                }
            }
        }
    }
    func testExpansionAtBottomDoesNotChangeSavedPosition() {
        let saved = FloatingPosition(screenID: "built-in", horizontal: 1, vertical: 1)
        let collapsed = OverlayGeometry.frame(for: saved, size: OverlayGeometry.collapsedSize, within: primary)
        let expanded = OverlayGeometry.frame(for: saved, size: OverlayGeometry.expandedSize, within: primary)
        expectTrue(primary.contains(expanded))
        expectEqual(expanded.minY, primary.minY + 8)
        expectEqual(expanded.maxX, collapsed.maxX)
        expectEqual(OverlayGeometry.frame(for: saved, size: OverlayGeometry.collapsedSize, within: primary), collapsed)
    }
    func testScreenResizeAndOffscreenRecovery() {
        let small = CGRect(x: -600, y: 200, width: 360, height: 200)
        let frame = OverlayGeometry.frame(for: .init(screenID: "removed", horizontal: 1, vertical: 1), size: OverlayGeometry.expandedSize, within: small)
        expectTrue(small.contains(frame))
        expectEqual(frame.width, 344)
        expectEqual(frame.height, 184)
        let outside = CGRect(x: -5000, y: 3000, width: 430, height: 278)
        expectTrue(primary.contains(OverlayGeometry.clamp(outside, within: primary)))
    }
    func testSafeAreaAvoidsNotchAndDock() {
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let visible = CGRect(x: 0, y: 70, width: 1470, height: 886)
        let usable = OverlayGeometry.usableFrame(frame: frame, visibleFrame: visible, safeTop: 37)
        expectEqual(usable.minY, 70)
        expectEqual(usable.maxY, 919)
        let top = OverlayGeometry.frame(for: .init(screenID: "M4", horizontal: 0.5, vertical: 0), size: OverlayGeometry.collapsedSize, within: usable)
        expectEqual(top.maxY, 911)
    }
    func testPreferencesPersistAndClampInvalidValues() throws {
        final class MemoryDefaults: UserDefaults {
            var stored: [String: Data] = [:]
            override func data(forKey defaultName: String) -> Data? { stored[defaultName] }
            override func set(_ value: Any?, forKey defaultName: String) { stored[defaultName] = value as? Data }
        }
        let defaults = MemoryDefaults(suiteName: "MacBuddy-overlay-test")!
        expectEqual(OverlayPreferences.load(from: defaults), OverlayPreferences())
        var prefs = OverlayPreferences()
        prefs.backgroundOpacity = 0.8; prefs.positionLocked = true
        prefs.floatingPosition = .init(screenID: "stable-display-uuid", horizontal: 0.27, vertical: 0.81)
        prefs.save(to: defaults)
        expectEqual(OverlayPreferences.load(from: defaults), prefs)
        prefs.backgroundOpacity = -2; prefs.floatingPosition?.horizontal = 5
        prefs.save(to: defaults)
        let restored = OverlayPreferences.load(from: defaults)
        expectEqual(restored.backgroundOpacity, 0.6)
        expectEqual(restored.floatingPosition?.horizontal, 1)
        prefs.backgroundOpacity = .nan
        expectEqual(prefs.sanitized.backgroundOpacity, 0.7)
        defaults.stored["overlayPreferences"] = Data("{\"backgroundOpacity\":0.85}".utf8)
        expectEqual(OverlayPreferences.load(from: defaults).backgroundOpacity, 0.85)
        expectTrue(!OverlayPreferences.load(from: defaults).positionLocked)
        defaults.stored["overlayPreferences"] = Data("corrupt preference".utf8)
        expectEqual(OverlayPreferences.load(from: defaults), OverlayPreferences())
    }
}
