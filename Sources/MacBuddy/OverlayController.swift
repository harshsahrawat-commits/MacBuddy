import AppKit
import SwiftUI
import MacBuddyCore
import os

private final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class OverlayController: NSObject {
    private let model: MonitorModel
    private let panel: BuddyPanel
    private let replyPanel: BuddyPanel
    private var visibilityOverride: Bool?
    private var dragOrigin: NSPoint?
    private let logger = Logger(subsystem: "app.macbuddy.personal", category: "state")
    var preferredScreen: (() -> NSScreen?)?
    init(model: MonitorModel) {
        self.model = model
        panel = BuddyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        replyPanel = BuddyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.animationBehavior = .none
        panel.title = "Mac Buddy floating display"
        replyPanel.isFloatingPanel = true; replyPanel.hidesOnDeactivate = false; replyPanel.isReleasedWhenClosed = false
        replyPanel.level = .floating; replyPanel.collectionBehavior = panel.collectionBehavior
        replyPanel.isOpaque = false; replyPanel.backgroundColor = .clear; replyPanel.hasShadow = false
        replyPanel.animationBehavior = .none
        replyPanel.ignoresMouseEvents = true; replyPanel.title = "Pebble’s check-in"
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        model.onCompanionReplyChange = { [weak self] in self?.updateReply() }
        model.onDisplayChange = { [weak self] in self?.visibilityOverride = nil; self?.update() }
        model.onPlacementChange = { [weak self] in self?.update() }
        model.beginOverlayDrag = { [weak self] in self?.beginDrag() }
        model.moveOverlayDrag = { [weak self] origin in
            guard let self, self.dragOrigin != nil else { return }
            self.panel.setFrameOrigin(origin)
        }
        model.endOverlayDrag = { [weak self] in self?.finishDrag() }
        model.returnToNotch = { [weak self] in self?.returnToNotch() }
        model.centerOverlay = { [weak self] in self?.center() }
        model.nudgeOverlay = { [weak self] x, y in self?.nudge(x: x, y: y) }
        model.expandOverlay = { [weak self] in
            guard let self, self.dragOrigin == nil else { return }
            self.model.expanded.toggle(); self.model.configure(); self.update()
        }
    }
    private func screenID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return screen.localizedName }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() { return CFUUIDCreateString(nil, uuid) as String }
        return String(number.uint32Value)
    }
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0 && $0.safeAreaInsets.top > 0
        }
    }
    private func targetScreen() -> NSScreen? {
        if let position = model.overlayPreferences.floatingPosition {
            return NSScreen.screens.first { screenID($0) == position.screenID } ?? preferredScreen?() ?? NSScreen.main ?? NSScreen.screens.first
        }
        return notchScreen()
    }
    private func usable(_ screen: NSScreen) -> CGRect {
        OverlayGeometry.usableFrame(frame: screen.frame, visibleFrame: screen.visibleFrame, safeTop: screen.safeAreaInsets.top)
    }
    func update() {
        guard dragOrigin == nil else { return }
        let screen = targetScreen()
        if model.overlayAvailable != (screen != nil) { model.overlayAvailable = screen != nil }
        let visible = model.mode != "Off" && (visibilityOverride ?? (model.mode == "Always visible")) && screen != nil
        if model.overlayShown != visible { model.overlayShown = visible }
        guard visible, let screen else {
            if model.expanded { model.expanded = false; model.configure() }
            model.companionReply = nil
            if panel.isVisible { panel.orderOut(nil); log("overlay-hidden") }; return
        }
        let layout = OverlayGeometry.layout(for: model.overlayPreferences)
        if model.floatingLayout != layout { model.floatingLayout = layout }
        let anchorSize = OverlayGeometry.size(for: layout)
        let size = model.expanded ? OverlayGeometry.expandedSize : anchorSize
        let frame: CGRect
        if let position = model.overlayPreferences.floatingPosition {
            frame = OverlayGeometry.frame(for: position, size: size, within: usable(screen), anchorSize: anchorSize)
        } else {
            let width = min(size.width, screen.frame.width - 16)
            let center: CGFloat
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea { center = (left.maxX + right.minX) / 2 } else { center = screen.frame.midX }
            frame = OverlayGeometry.clamp(CGRect(x: min(max(screen.frame.minX + 8, center - width / 2), screen.frame.maxX - width - 8),
                           y: screen.frame.maxY - screen.safeAreaInsets.top - size.height - 4, width: width, height: size.height), within: usable(screen))
        }
        if panel.frame != frame { panel.setFrame(frame, display: true); updateReply() }
        if !panel.isVisible { panel.orderFrontRegardless(); log("overlay-visible") }
    }
    private func updateReply() {
        guard let message = model.companionReply, model.overlayShown, dragOrigin == nil, let screen = panel.screen else {
            replyPanel.orderOut(nil); replyPanel.contentView = nil; return
        }
        let view = NSHostingView(rootView: CompanionReplyView(message: message))
        let size = view.fittingSize
        let bounds = usable(screen)
        let below = panel.frame.minY - size.height - 6
        var x = panel.frame.minX + 24
        var y = below >= bounds.minY ? below : panel.frame.maxY + 6
        if model.expanded && panel.frame.maxX + size.width + 6 <= bounds.maxX {
            x = panel.frame.maxX + 6; y = panel.frame.maxY - size.height
        } else if model.expanded && panel.frame.minX - size.width - 6 >= bounds.minX {
            x = panel.frame.minX - size.width - 6; y = panel.frame.maxY - size.height
        }
        let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        replyPanel.contentView = view; replyPanel.setFrame(OverlayGeometry.clamp(frame, within: bounds), display: true)
        replyPanel.orderFrontRegardless()
    }
    func toggle() {
        if dragOrigin != nil { finishDrag() }
        guard model.mode != "Off" else { return }
        visibilityOverride = !model.overlayShown
        if visibilityOverride == false { model.expanded = false; model.configure() }
        update()
    }
    private func beginDrag() {
        guard !model.overlayPreferences.positionLocked, dragOrigin == nil else { return }
        model.companionReply = nil
        dragOrigin = panel.frame.origin
        log("overlay-drag-began")
    }
    private func finishDrag() {
        guard let origin = dragOrigin else { return }
        dragOrigin = nil
        defer { update() }
        guard hypot(panel.frame.minX - origin.x, panel.frame.minY - origin.y) > 2 else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        var preferences = model.overlayPreferences
        preferences.dockedEdge = preferences.style == .strip && preferences.autoVertical ? OverlayGeometry.nearbyEdge(of: panel.frame, within: usable(screen)) : nil
        let layout = OverlayGeometry.layout(for: preferences)
        var position = OverlayGeometry.position(for: panel.frame, screenID: screenID(screen), within: usable(screen), anchorSize: OverlayGeometry.size(for: layout))
        if let edge = preferences.dockedEdge { position.horizontal = edge == .left ? 0 : 1 }
        preferences.floatingPosition = position
        model.overlayPreferences = preferences
        log("overlay-dragged")
    }
    private func returnToNotch() {
        var preferences = model.overlayPreferences; preferences.floatingPosition = nil; preferences.dockedEdge = nil; model.overlayPreferences = preferences
        if model.mode != "Off" { visibilityOverride = true }; update()
    }
    private func center() {
        guard let screen = preferredScreen?() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        var preferences = model.overlayPreferences; preferences.floatingPosition = .init(screenID: screenID(screen), horizontal: 0.5, vertical: 0.5); preferences.dockedEdge = nil; model.overlayPreferences = preferences
        if model.mode != "Off" { visibilityOverride = true }; update()
    }
    private func nudge(x: CGFloat, y: CGFloat) {
        guard let screen = targetScreen() ?? preferredScreen?() ?? NSScreen.main else { return }
        let base = panel.frame.width > 1 ? panel.frame : OverlayGeometry.frame(for: model.overlayPreferences.floatingPosition ?? .init(screenID: screenID(screen), horizontal: 0.5, vertical: 0.5), size: OverlayGeometry.collapsedSize, within: usable(screen))
        let frame = base.offsetBy(dx: x, dy: y)
        var preferences = model.overlayPreferences
        let movingAway = preferences.dockedEdge == .left && x > 0 || preferences.dockedEdge == .right && x < 0
        preferences.dockedEdge = !movingAway && preferences.style == .strip && preferences.autoVertical ? OverlayGeometry.nearbyEdge(of: frame, within: usable(screen)) : nil
        var position = OverlayGeometry.position(for: frame, screenID: screenID(screen), within: usable(screen), anchorSize: OverlayGeometry.size(for: OverlayGeometry.layout(for: preferences)))
        if let edge = preferences.dockedEdge { position.horizontal = edge == .left ? 0 : 1 }
        preferences.floatingPosition = position; model.overlayPreferences = preferences
        if model.mode != "Off" { visibilityOverride = true }; update()
    }
    private func log(_ event: String) {
        let state = "\(event) overlay=\(model.overlayShown) expanded=\(model.expanded) floating=\(model.overlayPreferences.floatingPosition != nil)"
        logger.notice("\(state, privacy: .public)")
    }
    func stop() { dragOrigin = nil; model.companionReply = nil; replyPanel.orderOut(nil); panel.orderOut(nil) }
}
