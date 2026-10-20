import Foundation
import CoreGraphics

public struct FloatingPosition: Codable, Equatable {
    public var screenID: String
    public var horizontal: Double
    public var vertical: Double
    public init(screenID: String, horizontal: Double, vertical: Double) {
        self.screenID = screenID
        self.horizontal = Self.fraction(horizontal)
        self.vertical = Self.fraction(vertical)
    }
    private static func fraction(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.5 }
    public var sanitized: FloatingPosition { .init(screenID: screenID, horizontal: horizontal, vertical: vertical) }
}

public enum FloatingStyle: String, Codable, CaseIterable, Sendable { case strip = "Metric strip", avatar = "Pebble only" }
public enum FloatingEdge: String, Codable, Sendable { case left, right }
public enum FloatingLayout: String, Sendable { case horizontal, vertical, avatar }

public struct OverlayPreferences: Codable, Equatable {
    public var backgroundOpacity: Double = 0.70
    public var positionLocked = false
    public var floatingPosition: FloatingPosition?
    public var style: FloatingStyle = .strip
    public var autoVertical = true
    public var dockedEdge: FloatingEdge?
    public init() {}
    private enum CodingKeys: String, CodingKey { case backgroundOpacity, positionLocked, floatingPosition, style, autoVertical, dockedEdge }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        backgroundOpacity = try values.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.70
        positionLocked = try values.decodeIfPresent(Bool.self, forKey: .positionLocked) ?? false
        floatingPosition = try values.decodeIfPresent(FloatingPosition.self, forKey: .floatingPosition)
        style = (try? values.decode(FloatingStyle.self, forKey: .style)) ?? .strip
        autoVertical = (try? values.decode(Bool.self, forKey: .autoVertical)) ?? true
        dockedEdge = try? values.decode(FloatingEdge.self, forKey: .dockedEdge)
    }
    public var sanitized: OverlayPreferences {
        var result = self
        result.backgroundOpacity = backgroundOpacity.isFinite ? min(1, max(0.60, backgroundOpacity)) : 0.70
        result.floatingPosition = floatingPosition?.sanitized
        return result
    }
    public static func load(from defaults: UserDefaults) -> OverlayPreferences {
        guard let data = defaults.data(forKey: "overlayPreferences"),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return decoded.sanitized
    }
    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(sanitized) { defaults.set(data, forKey: "overlayPreferences") }
    }
}

/// AppKit screen coordinates (origin at bottom-left). Position is normalized to
/// the collapsed strip, so expansion/clamping never changes the saved anchor.
public enum OverlayGeometry {
    public static let collapsedSize = CGSize(width: 480, height: 68)
    public static let expandedSize = CGSize(width: 480, height: 560)
    public static let verticalSize = CGSize(width: 88, height: 306)
    public static let avatarSize = CGSize(width: 64, height: 64)
    public static func size(for layout: FloatingLayout) -> CGSize {
        switch layout { case .horizontal: return collapsedSize; case .vertical: return verticalSize; case .avatar: return avatarSize }
    }
    public static func layout(for preferences: OverlayPreferences) -> FloatingLayout {
        preferences.style == .avatar ? .avatar : preferences.autoVertical && preferences.dockedEdge != nil ? .vertical : .horizontal
    }
    public static func nearbyEdge(of frame: CGRect, within bounds: CGRect) -> FloatingEdge? {
        let region = inset(bounds)
        let left = frame.minX - region.minX, right = region.maxX - frame.maxX
        guard min(left, right) <= 32 else { return nil }
        return left < right ? .left : .right
    }
    public static let margin: CGFloat = 8
    public static func usableFrame(frame: CGRect, visibleFrame: CGRect, safeTop: CGFloat) -> CGRect {
        let top = min(visibleFrame.maxY, frame.maxY - max(0, safeTop))
        return CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: visibleFrame.width, height: max(1, top - visibleFrame.minY))
    }
    private static func inset(_ bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: min(margin, max(0, (bounds.width - 1) / 2)), dy: min(margin, max(0, (bounds.height - 1) / 2)))
    }
    public static func clamp(_ frame: CGRect, within bounds: CGRect) -> CGRect {
        let region = inset(bounds)
        let width = min(max(1, frame.width), region.width)
        let height = min(max(1, frame.height), region.height)
        return CGRect(x: min(max(region.minX, frame.minX), region.maxX - width),
                      y: min(max(region.minY, frame.minY), region.maxY - height), width: width, height: height)
    }
    public static func frame(for position: FloatingPosition, size: CGSize, within bounds: CGRect, anchorSize: CGSize = collapsedSize) -> CGRect {
        let position = position.sanitized
        let region = inset(bounds)
        let width = min(size.width, region.width)
        let travelX = max(0, region.width - min(anchorSize.width, region.width))
        let travelY = max(0, region.height - min(anchorSize.height, region.height))
        let left = region.minX + position.horizontal * travelX
        let top = region.maxY - position.vertical * travelY
        return clamp(CGRect(x: left, y: top - size.height, width: width, height: size.height), within: bounds)
    }
    public static func position(for frame: CGRect, screenID: String, within bounds: CGRect, anchorSize: CGSize? = nil) -> FloatingPosition {
        let region = inset(bounds)
        let fitted = clamp(frame, within: bounds)
        let travelX = max(0, region.width - min(anchorSize?.width ?? fitted.width, region.width))
        let travelY = max(0, region.height - min(anchorSize?.height ?? collapsedSize.height, region.height))
        return .init(screenID: screenID,
                     horizontal: travelX > 0 ? (fitted.minX - region.minX) / travelX : 0.5,
                     vertical: travelY > 0 ? (region.maxY - fitted.maxY) / travelY : 0)
    }
}
