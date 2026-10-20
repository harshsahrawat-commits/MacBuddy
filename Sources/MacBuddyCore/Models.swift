import Foundation

public enum Metric: String, Codable, CaseIterable, Sendable {
    case cpu, gpu, cpuTemperature, gpuTemperature, memoryUsed, memoryTotal, compressed, swapUsed, swapRate, diskFree, diskTotal, battery, uptime
    public var title: String {
        switch self {
        case .cpu: return "CPU"; case .gpu: return "GPU"
        case .cpuTemperature: return "CPU temperature"; case .gpuTemperature: return "GPU temperature"
        case .memoryUsed: return "Memory used (estimate)"; case .memoryTotal: return "Unified memory"
        case .compressed: return "Compressed memory"; case .swapUsed: return "Swap used"; case .swapRate: return "Swap-out activity"
        case .diskFree: return "Storage available"; case .diskTotal: return "Storage capacity"
        case .battery: return "Battery"; case .uptime: return "Uptime"
        }
    }
    public var unit: String {
        switch self {
        case .cpu, .gpu, .battery: return "%"
        case .cpuTemperature, .gpuTemperature: return "°C"
        case .swapRate: return "B/s"; case .uptime: return "s"
        default: return "B"
        }
    }
    public func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        switch unit {
        case "%": return String(format: "%.0f%%", value)
        case "°C": return String(format: "%.1f°C", value)
        case "B": return String(format: "%.1f GiB", value / 1_073_741_824)
        case "B/s": return String(format: "%.1f MiB/s", value / 1_048_576)
        default: return String(format: "%.1f days", value / 86400)
        }
    }
}

public struct Reading: Codable, Sendable {
    public var value: Double?
    public var timestamp: Date
    public var source: String
    public var unit: String
    public var unavailableReason: String?
    public init(_ value: Double?, at timestamp: Date, source: String, unit: String, reason: String? = nil) {
        self.value = value?.isFinite == true ? value : nil
        self.timestamp = timestamp; self.source = source; self.unit = unit
        unavailableReason = self.value == nil ? (reason ?? "This source is unavailable on this Mac.") : nil
    }
}

public enum Thermal: Int, Codable, CaseIterable, Sendable {
    case nominal, fair, serious, critical, unknown
    public var name: String { ["Nominal", "Fair", "Serious", "Critical", "Unavailable"][rawValue] }
    public var friendly: String { ["Cruising", "Warming up", "Time to ease up", "Take a breather", "Checking conditions"][rawValue] }
}
public enum Pressure: Int, Codable, Sendable {
    case unknown = 0, normal = 1, warning = 2, critical = 4
    public var name: String {
        switch self { case .unknown: return "Unavailable"; case .normal: return "Normal"; case .warning: return "Elevated"; case .critical: return "Critical" }
    }
}
public struct BatteryInfo: Codable, Sendable {
    public var powerSource: String
    public var condition: String?
    public var cycleCount: Int?
    public var maximumCapacityPercent: Double?
    public init(powerSource: String = "Unavailable", condition: String? = nil, cycleCount: Int? = nil, maximumCapacityPercent: Double? = nil) {
        self.powerSource = powerSource; self.condition = condition; self.cycleCount = cycleCount; self.maximumCapacityPercent = maximumCapacityPercent
    }
}
public struct Snapshot: Codable, Sendable {
    public var timestamp: Date
    public var readings: [Metric: Reading]
    public var thermal: Thermal
    public var pressure: Pressure
    public var batteryInfo: BatteryInfo
    public init(at timestamp: Date = Date(), readings: [Metric: Reading] = [:], thermal: Thermal = .unknown, pressure: Pressure = .unknown, batteryInfo: BatteryInfo = .init()) {
        self.timestamp = timestamp; self.readings = readings; self.thermal = thermal; self.pressure = pressure; self.batteryInfo = batteryInfo
    }
    public subscript(_ metric: Metric) -> Double? { readings[metric]?.value }
    public var memoryPercent: Double? {
        guard let used = self[.memoryUsed], let total = self[.memoryTotal], total > 0 else { return nil }
        return used / total * 100
    }
}
public struct ProcessReading: Identifiable, Sendable {
    public var pid: Int32
    public var birth: UInt64
    public var name: String
    public var cpuPercent: Double?
    public var memoryBytes: UInt64
    public var id: String { "\(pid)-\(birth)" }
}
public struct ProcessCounter: Sendable {
    public var pid: Int32; public var birth: UInt64; public var name: String; public var cpuNanoseconds: UInt64; public var footprint: UInt64
    public init(pid: Int32, birth: UInt64, name: String, cpuNanoseconds: UInt64, footprint: UInt64) {
        self.pid = pid; self.birth = birth; self.name = name; self.cpuNanoseconds = cpuNanoseconds; self.footprint = footprint
    }
}
public struct ProcessTracker {
    private var previous: [Int32: ProcessCounter] = [:]
    private var previousTime: TimeInterval?
    public init() {}
    public mutating func reset() { previous = [:]; previousTime = nil }
    public mutating func update(_ counters: [ProcessCounter], time: TimeInterval) -> [ProcessReading] {
        let elapsed = previousTime.map { time - $0 }
        defer { previous = Dictionary(counters.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last }); previousTime = time }
        return counters.map { current in
            var cpu: Double?
            if let old = previous[current.pid], old.birth == current.birth, let elapsed, elapsed > 0, elapsed <= 15, current.cpuNanoseconds >= old.cpuNanoseconds {
                cpu = Double(current.cpuNanoseconds - old.cpuNanoseconds) / 1e9 / elapsed * 100
            }
            return ProcessReading(pid: current.pid, birth: current.birth, name: current.name, cpuPercent: cpu, memoryBytes: current.footprint)
        }
    }
}
