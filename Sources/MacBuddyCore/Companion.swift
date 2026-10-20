import Foundation

public enum PebbleExpression: String, Sendable { case normal, focused, attention, recovering, relieved, checking }

/// Presentation only: the advice engine remains the authority for incidents and recovery.
public struct CompanionPresentation: Equatable, Sendable {
    public var expression: PebbleExpression
    public var status: String
    public var category: String
    public var heading: String
    public var detail: String
    public var action: String
    public var lines: [String]
    public static let checking = CompanionPresentation(expression: .checking, status: "Checking", category: "RIGHT NOW",
        heading: "Getting our bearings.", detail: "Waiting for monitoring data.", action: "Unavailable readings are never treated as zero.",
        lines: ["Getting my bearings. The numbers will be along shortly."])
}

public struct CompanionTracker {
    private var previous: [Advice] = []
    private var lastDate: Date?
    private var recoveredAt: Date?
    public init() {}

    public mutating func update(_ sample: Snapshot, advice: [Advice]) -> CompanionPresentation {
        let now = sample.timestamp
        let continuous = lastDate.map { now > $0 && now.timeIntervalSince($0) <= 15 } ?? false
        if !continuous { previous = []; recoveredAt = nil }
        // Only a previously recovering incident disappearing during continuous
        // engine updates proves recovery. Sleep, missing data or a restart do not.
        if previous.contains(where: { old in old.recovering && !advice.contains(where: { $0.category == old.category }) }) {
            recoveredAt = now
        }
        previous = advice; lastDate = now
        let conditions = "Memory pressure: \(sample.pressure.name). Thermal state: \(sample.thermal.name)."
        if let active = advice.first(where: { !$0.recovering }) ?? advice.first {
            recoveredAt = nil
            let recovering = active.recovering
            let expression: PebbleExpression = recovering ? .recovering : active.category == .capacity ? .focused : .attention
            let status = recovering ? "Settling" : active.category == .capacity ? "Busy" : active.category == .memory ? "Memory" : active.category == .storage ? "Storage" : sample.thermal.friendly
            return .init(expression: expression, status: status, category: recovering ? "RECOVERING" : active.category.rawValue.uppercased(),
                heading: recovering ? "Settling back down." : active.title,
                detail: recovering ? "The advisory stays active until two stable minutes are observed. \(conditions)" : active.evidence,
                action: active.action,
                lines: recovering ? ["Things are settling. I’m watching for two steady minutes before calling it recovered.", "Looking better. Let’s give it a little time to stay that way."] : [active.evidence + " " + active.action, active.action])
        }
        // Show current conditions immediately, without inventing a sustained incident.
        if sample.pressure == .warning || sample.pressure == .critical {
            return .init(expression: .attention, status: "Memory", category: "MEMORY PRESSURE", heading: "Memory needs some room.", detail: conditions,
                action: "Review the largest memory consumers before adding more heavy work.", lines: ["Memory pressure is elevated. Let’s review the biggest memory users."])
        }
        if sample.thermal != .nominal && sample.thermal != .unknown {
            return .init(expression: .attention, status: sample.thermal.friendly, category: "THERMAL CONDITIONS", heading: sample.thermal.friendly,
                detail: conditions, action: "Reduce simultaneous heavy work; keep the Mac on a hard, ventilated surface.",
                lines: ["macOS reports \(sample.thermal.name.lowercased()) thermal conditions. Reducing simultaneous heavy work could help."])
        }
        if (sample[.cpu] ?? 0) > 90 || (sample[.gpu] ?? 0) > 90 {
            let resource = (sample[.cpu] ?? 0) > 90 ? "CPU" : "GPU"
            return .init(expression: .focused, status: "\(resource) busy", category: "CURRENT WORKLOAD", heading: "A busy moment.",
                detail: "\(resource) is above 90% right now. A brief burst is not a sustained advisory. \(conditions)",
                action: "Heavy work can be intentional. I’ll keep watching for sustained load.",
                lines: ["Your \(resource) has a full plate right now. I’m watching whether it lasts.", "Busy can be perfectly intentional. I’ll mind the numbers."])
        }
        guard sample[.cpu] != nil || sample[.gpu] != nil || sample.memoryPercent != nil else { return .checking }
        let incomplete = sample[.cpu] == nil || sample[.gpu] == nil || sample.memoryPercent == nil || sample.thermal == .unknown || sample.pressure == .unknown
        if let recoveredAt, now.timeIntervalSince(recoveredAt) < 30 {
            return .init(expression: .relieved, status: "Recovered", category: "BACK TO STEADY", heading: "A little breathing room.",
                detail: "The advisory resolved after two stable minutes. \(conditions)" + (incomplete ? " Some readings remain unavailable." : ""), action: "Monitoring continues.",
                lines: ["The advisory has settled after two stable minutes." + (incomplete ? " A few other readings are still unavailable." : " Love to see it."), "A little breathing room again. I’ll keep an eye on things."])
        }
        if incomplete {
            recoveredAt = nil
            return .init(expression: .checking, status: "Partial data", category: "SOURCE AVAILABILITY", heading: "Some readings are unavailable.",
                detail: conditions, action: "Available readings continue updating. Open the dashboard for source details.",
                lines: ["I can see some of the picture. A few readings are unavailable, so I won’t guess."])
        }
        return .init(expression: .normal, status: "Steady", category: "RIGHT NOW", heading: "All steady.", detail: conditions,
            action: "No sustained bottlenecks detected.",
            lines: ["Looks good. You do the thinking; I’ll mind the numbers.", "All steady. A little room for your next big idea.", "Nice and steady over here. Carry on."])
    }
}
