import Foundation
import NativeTelemetry
import IOKit
import IOKit.ps

public protocol MetricProviding: AnyObject {
    func sample(at date: Date) -> Snapshot
    func processes() -> [ProcessReading]
    func reset()
}

/// All access is serialized by the sampling queue. Undocumented SMC / AGX reads live in NativeTelemetry.
public final class TelemetryProvider: MetricProviding {
    private var previousCPU: [UInt32]?
    private var previousSwap: (UInt64, TimeInterval)?
    private var processTracker = ProcessTracker()
    private var diskReadings: [Metric: Reading] = [:]
    private var lastDisk = Date.distantPast
    public init() {}
    public func reset() {
        previousCPU = nil; previousSwap = nil; processTracker.reset(); lastDisk = .distantPast
        mb_close_sensors()
    }
    public func sample(at date: Date = Date()) -> Snapshot {
        var raw = MBMetrics(); mb_read_metrics(&raw)
        var readings: [Metric: Reading] = [:]
        func put(_ key: Metric, _ value: Double?, _ source: String, _ reason: String? = nil) {
            readings[key] = Reading(value, at: date, source: source, unit: key.unit, reason: reason)
        }
        var cpu: Double?
        if raw.cpu_valid != 0 {
            let ticks = [raw.cpu_user, raw.cpu_system, raw.cpu_idle, raw.cpu_nice].map { UInt32(truncatingIfNeeded: $0) }
            if let previousCPU {
                let deltas = zip(ticks, previousCPU).map { UInt64($0 &- $1) }
                let total = deltas.reduce(0, +)
                if total > 0 { cpu = Double(total - deltas[2]) / Double(total) * 100 }
            }
            previousCPU = ticks
        } else { previousCPU = nil }
        put(.cpu, cpu, "Mach host CPU tick deltas", "Waiting for two valid CPU samples.")
        put(.gpu, raw.gpu_valid != 0 ? raw.gpu_percent : nil, "IORegistry AGX Device Utilization % (undocumented)")
        put(.cpuTemperature, raw.cpu_temperature_valid != 0 ? raw.cpu_temperature : nil, "Read-only AppleSMC M4 CPU mean (\(raw.cpu_sensor_count) sensors; undocumented)")
        put(.gpuTemperature, raw.gpu_temperature_valid != 0 ? raw.gpu_temperature : nil, "Read-only AppleSMC M4 GPU mean (\(raw.gpu_sensor_count) sensors; undocumented)")
        put(.memoryUsed, raw.memory_valid != 0 ? Double(raw.memory_used) : nil, "Mach VM estimate: app + wired + compressor; may differ from Activity Monitor's total accounting")
        put(.memoryTotal, raw.memory_valid != 0 ? Double(raw.memory_total) : nil, "sysctl hw.memsize")
        put(.compressed, raw.memory_valid != 0 ? Double(raw.compressed) : nil, "Mach compressor physical pages")
        put(.swapUsed, raw.swap_valid != 0 ? Double(raw.swap_used) : nil, "sysctl vm.swapusage")
        let clock = ProcessInfo.processInfo.systemUptime
        var rate: Double?
        if raw.memory_valid != 0 {
            if let (old, time) = previousSwap, clock > time, clock - time <= 15, raw.swapout_bytes >= old {
                rate = Double(raw.swapout_bytes - old) / (clock - time)
            }
            previousSwap = (raw.swapout_bytes, clock)
        } else { previousSwap = nil }
        put(.swapRate, rate, "Mach swap-out byte delta / awake second", "Waiting for consecutive swap samples.")
        put(.uptime, clock, "ProcessInfo.systemUptime")
        if date.timeIntervalSince(lastDisk) >= 60 || date < lastDisk {
            let volume = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            diskReadings[.diskFree] = Reading(values?.volumeAvailableCapacityForImportantUsage.map(Double.init), at: date, source: "Startup data volume capacity available for important usage", unit: "B")
            diskReadings[.diskTotal] = Reading(values?.volumeTotalCapacity.map(Double.init), at: date, source: "Startup data volume capacity", unit: "B")
            lastDisk = date
        }
        readings.merge(diskReadings, uniquingKeysWith: { _, new in new })
        let (charge, battery) = readBattery()
        put(.battery, charge, "IOPowerSources internal battery")
        let thermal: Thermal
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal; case .fair: thermal = .fair
        case .serious: thermal = .serious; case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        return Snapshot(at: date, readings: readings, thermal: thermal, pressure: raw.pressure_valid != 0 ? Pressure(rawValue: Int(raw.pressure)) ?? .unknown : .unknown, batteryInfo: battery)
    }
    public func processes() -> [ProcessReading] {
        var native = [MBProcess](repeating: MBProcess(), count: 4096)
        let count = native.withUnsafeMutableBufferPointer { mb_read_processes($0.baseAddress, $0.count) }
        let counters = native.prefix(count).map { item -> ProcessCounter in
            var name = item.name
            let label = withUnsafePointer(to: &name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            return ProcessCounter(pid: item.pid, birth: item.birth, name: label, cpuNanoseconds: item.cpu_nanoseconds, footprint: item.footprint)
        }
        return processTracker.update(counters, time: ProcessInfo.processInfo.systemUptime)
    }
    private func readBattery() -> (Double?, BatteryInfo) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, .init()) }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = (info[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let max = (info[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let charge = current.flatMap { c in max.flatMap { $0 > 0 ? c / $0 * 100 : nil } }
            var battery = BatteryInfo(powerSource: info[kIOPSPowerSourceStateKey] as? String ?? "Unavailable", condition: info[kIOPSBatteryHealthKey] as? String)
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                battery.cycleCount = (IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
                // Do not confuse current charge or raw design capacity ratios with Apple's health estimate.
                battery.maximumCapacityPercent = (IORegistryEntryCreateCFProperty(service, "MaximumCapacityPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue
            }
            return (charge, battery)
        }
        return (nil, .init(powerSource: "No internal battery reported"))
    }
}
