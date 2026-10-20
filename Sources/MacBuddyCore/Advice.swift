import Foundation

public struct AdvicePolicy: Sendable {
    public var fairDuration: TimeInterval = 30
    public var seriousDuration: TimeInterval = 10
    public var memoryDuration: TimeInterval = 120
    public var capacityDuration: TimeInterval = 120
    public var storageDuration: TimeInterval = 300
    public var storageCriticalDuration: TimeInterval = 60
    public var recoveryDuration: TimeInterval = 120
    public var cooldown: TimeInterval = 900
    public var highMemoryPercent = 85.0
    public var highLoadPercent = 90.0
    public var compressionGrowthBytes = 64.0 * 1_048_576
    public var swapBytesPerSecond = 1_048_576.0
    public init() {}
}
public enum AdviceCategory: String, Codable, CaseIterable, Sendable { case thermal, memory, capacity, storage }
public struct Advice: Identifiable, Codable, Sendable {
    public var category: AdviceCategory
    public var severity: Int
    public var title: String
    public var evidence: String
    public var action: String
    public var since: Date
    public var recovering: Bool = false
    public var id: String { category.rawValue }
}
public struct AdviceUpdate: Sendable {
    public var active: [Advice]
    public var notifications: [Advice]
}

/// Heuristics concern responsiveness, not component damage or certified limits.
public struct AdviceEngine {
    public let policy: AdvicePolicy
    private var starts: [String: Date] = [:]
    private var incidents: [AdviceCategory: Advice] = [:]
    private var recoveries: [AdviceCategory: Date] = [:]
    private var notices: [AdviceCategory: (Date, Int)] = [:]
    // Only resources that actually triggered this incident must be observable to
    // prove recovery. An optional GPU adapter must not strand a CPU-only notice.
    private var capacityResources: Set<Metric> = []
    private var window: [Snapshot] = []
    private var lastDate: Date?
    public init(policy: AdvicePolicy = .init()) { self.policy = policy }
    public mutating func resetContinuity() { starts = [:]; recoveries = [:]; window = []; lastDate = nil }
    private mutating func sustained(_ key: String, _ predicate: Bool, _ duration: TimeInterval, _ now: Date) -> Bool {
        guard predicate else { starts[key] = nil; return false }
        if starts[key] == nil { starts[key] = now }
        return now.timeIntervalSince(starts[key]!) >= duration
    }
    public mutating func update(_ s: Snapshot, notificationsAllowed: Bool = true) -> AdviceUpdate {
        let now = s.timestamp
        if let lastDate, now.timeIntervalSince(lastDate) > 15 || now <= lastDate { resetContinuity() }
        lastDate = now
        let windowDuration = policy.memoryDuration + 5
        window.append(s); window.removeAll { now.timeIntervalSince($0.timestamp) > windowDuration }
        var candidates: [AdviceCategory: Advice] = [:]
        func advice(_ category: AdviceCategory, _ severity: Int, _ title: String, _ evidence: String, _ action: String) -> Advice {
            Advice(category: category, severity: severity, title: title, evidence: evidence, action: action, since: now)
        }
        let fair = sustained("fair", s.thermal != .unknown && s.thermal.rawValue >= Thermal.fair.rawValue, policy.fairDuration, now)
        let serious = sustained("serious", s.thermal != .unknown && s.thermal.rawValue >= Thermal.serious.rawValue, policy.seriousDuration, now)
        if s.thermal == .critical || serious || fair {
            let severity = s.thermal == .critical ? 3 : serious ? 2 : 1
            candidates[.thermal] = advice(.thermal, severity, s.thermal.friendly,
                "macOS reports \(s.thermal.name) thermal conditions. This classification comes from macOS, not a Celsius threshold.",
                "Reduce simultaneous builds or other heavy work; keep the Mac on a hard, ventilated surface.")
        }
        let highMemory = sustained("highMemory", (s.memoryPercent ?? 0) > policy.highMemoryPercent, policy.memoryDuration, now)
        let swapping = sustained("swapping", (s[.swapRate] ?? 0) > policy.swapBytesPerSecond, policy.memoryDuration, now)
        // Every quarter of the two-minute window must show compression growth. A single jump is insufficient.
        let compressionGrowing: Bool = {
            guard highMemory, let first = window.first, now.timeIntervalSince(first.timestamp) >= policy.memoryDuration,
                  let initial = first[.compressed], let final = s[.compressed], final - initial >= policy.compressionGrowthBytes else { return false }
            var prior = initial
            for quarter in 1...4 {
                let target = now.addingTimeInterval(-policy.memoryDuration + policy.memoryDuration * Double(quarter) / 4)
                guard let value = window.first(where: { $0.timestamp >= target })?[.compressed], value > prior else { return false }
                prior = value
            }
            return true
        }()
        if s.pressure == .warning || s.pressure == .critical || (highMemory && (swapping || compressionGrowing)) {
            candidates[.memory] = advice(.memory, s.pressure == .critical ? 3 : s.pressure == .warning ? 2 : 1,
                "Give your memory some room", s.pressure == .warning || s.pressure == .critical ? "System memory pressure is \(s.pressure.name.lowercased())." : "Memory usage stayed above 85% for two minutes with sustained compression growth or swap-out activity.",
                "Review the largest memory consumers in Activity Monitor. Consider fewer concurrent coding sessions.")
        }
        let cpu = sustained("cpu", (s[.cpu] ?? 0) > policy.highLoadPercent, policy.capacityDuration, now)
        let gpu = sustained("gpu", (s[.gpu] ?? 0) > policy.highLoadPercent, policy.capacityDuration, now)
        if cpu || gpu {
            if cpu { capacityResources.insert(.cpu) }
            if gpu { capacityResources.insert(.gpu) }
            let resources = cpu && gpu ? "CPU and GPU" : cpu ? "CPU" : "GPU"
            candidates[.capacity] = advice(.capacity, 1, "Workload near capacity", "\(resources) utilization stayed above 90% for two minutes. This is a workload advisory, not a hardware warning.", "Finish or pause a demanding task before starting another build.")
        }
        let diskValid = s[.diskFree] != nil && s[.diskTotal] != nil && now.timeIntervalSince(s.readings[.diskFree]?.timestamp ?? .distantPast) <= 90
        let low = diskValid && s[.diskFree]! < max(20 * 1_073_741_824, s[.diskTotal]! * 0.1)
        let veryLow = diskValid && s[.diskFree]! < max(5 * 1_073_741_824, s[.diskTotal]! * 0.02)
        let storageLow = sustained("disk", low, policy.storageDuration, now)
        let storageCritical = sustained("diskCritical", veryLow, policy.storageCriticalDuration, now)
        if storageLow || storageCritical {
            candidates[.storage] = advice(.storage, storageCritical ? 2 : 1, "Make space for your work", "\(Metric.diskFree.format(s[.diskFree])) available; below Mac Buddy's \(storageCritical ? "critical threshold for one minute" : "low-space threshold for five minutes").", "Review storage in System Settings and remove files you no longer need.")
        }
        let healthy: [AdviceCategory: Bool] = [
            .thermal: s.thermal == .nominal,
            .memory: s.pressure == .normal && s.memoryPercent != nil && s[.compressed] != nil && s[.swapRate] != nil && !(highMemory && (swapping || compressionGrowing)),
            .capacity: !capacityResources.isEmpty && capacityResources.allSatisfy { metric in
                s[metric].map { $0 <= policy.highLoadPercent } ?? false
            } && ![Metric.cpu, .gpu].contains { (s[$0] ?? 0) > policy.highLoadPercent },
            .storage: diskValid && !low
        ]
        var notifications: [Advice] = []
        for category in AdviceCategory.allCases {
            if var candidate = candidates[category] {
                candidate.since = incidents[category]?.since ?? now
                // Preserve severity until a real recovery, avoiding repeated escalation on oscillation.
                candidate.severity = max(candidate.severity, incidents[category]?.severity ?? 0)
                incidents[category] = candidate; recoveries[category] = nil
                let old = notices[category]
                if notificationsAllowed && (old == nil || candidate.severity > old!.1 || now.timeIntervalSince(old!.0) >= policy.cooldown) {
                    notifications.append(candidate); notices[category] = (now, candidate.severity)
                }
            } else if incidents[category] != nil {
                if healthy[category] == true {
                    if recoveries[category] == nil { recoveries[category] = now }
                    if now.timeIntervalSince(recoveries[category]!) >= policy.recoveryDuration {
                        incidents[category] = nil; recoveries[category] = nil
                        if category == .capacity { capacityResources.removeAll() }
                    } else { incidents[category]?.recovering = true }
                } else { recoveries[category] = nil; incidents[category]?.recovering = false }
            }
        }
        return AdviceUpdate(active: incidents.values.sorted { $0.severity == $1.severity ? $0.id < $1.id : $0.severity > $1.severity }, notifications: notifications)
    }
}
