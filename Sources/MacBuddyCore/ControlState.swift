import Foundation

/// Guards asynchronous permission callbacks against later user choices.
public struct NotificationPermissionState {
    public enum Authorization { case notDetermined, denied, allowed }
    public private(set) var enabled = false
    public private(set) var authorization: Authorization = .notDetermined
    public private(set) var generation: UInt64 = 0
    public var canDeliver: Bool { enabled && authorization == .allowed }
    public init() {}
    @discardableResult public mutating func begin(enabled: Bool) -> UInt64 {
        generation &+= 1; self.enabled = enabled
        if !enabled { authorization = .notDetermined }
        return generation
    }
    public func isCurrent(_ request: UInt64) -> Bool { request == generation && enabled }
    @discardableResult public mutating func complete(_ request: UInt64, authorization: Authorization) -> Bool {
        guard isCurrent(request) else { return false }
        self.authorization = authorization; return true
    }
}

public enum HistoryRange {
    public static func throughDay(_ day: Date, calendar: Calendar, now: Date) -> Date {
        min(now, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? now)
    }
}
