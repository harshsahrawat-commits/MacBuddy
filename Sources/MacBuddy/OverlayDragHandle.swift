import AppKit
import SwiftUI

struct OverlayDragHandle: NSViewRepresentable {
    var locked: Bool
    var begin: () -> Void
    var move: (NSPoint) -> Void
    var end: () -> Void
    var showsDots = true
    var click: (() -> Void)? = nil
    var hover: ((Bool) -> Void)? = nil
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.locked = locked; view.begin = begin; view.move = move; view.end = end
        view.showsDots = showsDots; view.click = click; view.hover = hover
        view.toolTip = locked ? "Position locked. Unlock in Settings to drag." : "Drag to move Mac Buddy. Placement controls are also in Settings."
        view.setAccessibilityRole(click == nil ? .image : .button)
        view.setAccessibilityLabel(click == nil ? (locked ? "Position locked" : "Move Mac Buddy") : "Pebble. Click for details or drag to move")
        view.setAccessibilityHelp("Use Placement in Settings for keyboard positioning or to return to the notch.")
        view.window?.invalidateCursorRects(for: view)
        view.needsDisplay = true
    }
    final class HandleView: NSView {
        var locked = false
        var begin: (() -> Void)?
        var move: ((NSPoint) -> Void)?
        var end: (() -> Void)?
        var showsDots = true
        var click: (() -> Void)?
        var hover: ((Bool) -> Void)?
        private var grabOffset: NSPoint?
        private var startPoint: NSPoint?
        private var dragged = false
        private var hoverArea: NSTrackingArea?
        override init(frame: NSRect) { super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.image) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override var acceptsFirstResponder: Bool { false }
        override var needsPanelToBecomeKey: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: locked ? .arrow : .openHand) }
        override func draw(_ dirtyRect: NSRect) {
            guard showsDots else { return }
            NSColor.white.withAlphaComponent(locked ? 0.45 : 0.9).setFill()
            for x in [-2.5, 2.5] {
                for y in [-5.0, 0, 5.0] {
                    NSBezierPath(ovalIn: NSRect(x: bounds.midX + x - 1, y: bounds.midY + y - 1, width: 2, height: 2)).fill()
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            guard window != nil, !locked || click != nil else { return }
            grabOffset = event.locationInWindow
            startPoint = NSEvent.mouseLocation; dragged = false
            if !locked { begin?() }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let offset = grabOffset else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            if let startPoint, hypot(pointer.x-startPoint.x, pointer.y-startPoint.y) > 3 { dragged = true }
            guard !locked else { return }
            NSCursor.closedHand.set()
            move?(NSPoint(x: pointer.x - offset.x, y: pointer.y - offset.y))
        }
        override func mouseUp(with event: NSEvent) {
            guard grabOffset != nil else { return }
            grabOffset = nil
            if !locked { end?() }
            if !dragged { click?() }
            startPoint = nil
            NSCursor.openHand.set()
        }
        override func accessibilityPerformPress() -> Bool { guard let click else { return false }; click(); return true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area); hoverArea = area
        }
        override func mouseEntered(with event: NSEvent) { hover?(true) }
        override func mouseExited(with event: NSEvent) { hover?(false) }
    }
}
