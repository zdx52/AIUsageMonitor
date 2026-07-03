import Foundation
import IOKit
import Darwin

// MARK: - 温度数据

struct TemperatureData {
    let thermalState: ProcessInfo.ThermalState
    let cpuUsage: Double?  // 0-100%
    let batteryTemperature: Double?  // 摄氏度
    let cpuTemperature: Double?  // CPU 温度（通过 smctemp -c 读取）
    let gpuTemperature: Double?  // GPU 温度（通过 smctemp -g 读取）

    var thermalStateLabel: String {
        switch thermalState {
        case .nominal:   return "正常"
        case .fair:      return "偏高"
        case .serious:   return "严重"
        case .critical:  return "临界"
        @unknown default: return "未知"
        }
    }

    var thermalStateIcon: String {
        switch thermalState {
        case .nominal:   return "thermometer.low"
        case .fair:      return "thermometer.medium"
        case .serious:   return "thermometer.high"
        case .critical:  return "exclamationmark.triangle.fill"
        @unknown default: return "thermometer"
        }
    }
}

// MARK: - 温度监控

class TemperatureMonitor {
    static let shared = TemperatureMonitor()
    private var previousSample: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    private init() {}

    func getStatus() -> TemperatureData {
        TemperatureData(
            thermalState: ProcessInfo.processInfo.thermalState,
            cpuUsage: getCPUUsage(),
            batteryTemperature: getBatteryTemperature(),
            cpuTemperature: getCPUTemperature(),
            gpuTemperature: getGPUTemperature()
        )
    }

    /// smctemp 的候选路径（GUI 应用默认 PATH 不含 /usr/local/bin）
    private let smctempPaths = [
        "/usr/local/bin/smctemp",
        "/opt/homebrew/bin/smctemp",
    ]

    /// 通过 smctemp -c 获取 CPU 温度
    private func getCPUTemperature() -> Double? {
        return runSmctemp(arg: "-c")
    }

    /// 通过 smctemp -g 获取 GPU 温度
    private func getGPUTemperature() -> Double? {
        return runSmctemp(arg: "-g")
    }

    /// 用绝对路径调用 smctemp，不受 GUI 最小 PATH 影响
    private func runSmctemp(arg: String) -> Double? {
        guard let smctempPath = smctempPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            print("⚠️ smctemp 未找到，尝试路径: \(smctempPaths)")
            return nil
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: smctempPath)
        task.arguments = [arg]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return nil }
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(output ?? "")
        } catch {
            return nil
        }
    }

    /// 通过 Mach API 获取实时 CPU 使用率（两次采样差值）
    private func getCPUUsage() -> Double? {
        let current = readCPULoad()
        defer { previousSample = current }

        guard let prev = previousSample else { return nil }

        let totalDelta = (current.user + current.system + current.idle + current.nice)
                       - (prev.user + prev.system + prev.idle + prev.nice)
        let busyDelta  = (current.user + current.system + current.nice)
                       - (prev.user + prev.system + prev.nice)
        guard totalDelta > 0 else { return nil }

        return (Double(busyDelta) / Double(totalDelta)) * 100.0
    }

    private func readCPULoad() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return (
            user:   UInt64(cpuLoad.cpu_ticks.0),  // CPU_STATE_USER
            system: UInt64(cpuLoad.cpu_ticks.1),  // CPU_STATE_SYSTEM
            idle:   UInt64(cpuLoad.cpu_ticks.2),  // CPU_STATE_IDLE
            nice:   UInt64(cpuLoad.cpu_ticks.3)   // CPU_STATE_NICE
        )
    }

    /// 通过 IORegistry 读取电池温度（AppleSmartBattery 的 Temperature 字段，单位 1/100 °C）
    private func getBatteryTemperature() -> Double? {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let val = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int else {
            return nil
        }
        return Double(val) / 100.0
    }
}
