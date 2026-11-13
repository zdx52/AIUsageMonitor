import Foundation

// MARK: - 网络速度采样

class NetworkSpeedMonitor {
    static let shared = NetworkSpeedMonitor()

    /// 上一次采样：每个网卡的 32 位收发计数（getifaddrs 只给 if_data 的 u_int32_t）
    private var previous: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var previousTime: UInt64?

    /// 单次采样增量上限 1 GiB：超过即视为接口重置，不是真实流量
    private static let maxDelta: UInt64 = 1 << 30

    struct Speed {
        let upload: String   // 上传速度，如 "1.2 MB/s" 或 "512 KB/s"
        let download: String // 下载速度，如 "3.5 MB/s"
    }

    /// 获取当前网速（每秒调用一次）
    func getSpeed() -> Speed? {
        guard let current = readCounters() else { return nil }
        let now = DispatchTime.now().uptimeNanoseconds   // 单调时钟，不受系统改时间影响
        defer {
            previous = current
            previousTime = now
        }

        guard let lastTime = previousTime else { return nil }
        let elapsed = Double(now - lastTime) / 1_000_000_000
        guard elapsed > 0 else { return nil }

        var rxDelta: UInt64 = 0
        var txDelta: UInt64 = 0
        for (name, cur) in current {
            guard let prev = previous[name] else { continue }  // 新出现的接口本帧不计
            rxDelta += Self.delta(prev.rx, cur.rx)
            txDelta += Self.delta(prev.tx, cur.tx)
        }

        return Speed(
            upload: formatSpeed(Double(txDelta) / elapsed),
            download: formatSpeed(Double(rxDelta) / elapsed)
        )
    }

    /// 32 位计数器差值，新值小于旧值即回绕一次（每 4 GiB 一轮，逐网卡补偿）
    private static func delta(_ prev: UInt32, _ cur: UInt32) -> UInt64 {
        let d: UInt64 = cur >= prev
            ? UInt64(cur - prev)
            : UInt64(UInt32.max - prev) + 1 + UInt64(cur)
        return d > maxDelta ? 0 : d
    }

    /// 读取所有活跃物理接口的收发字节数
    private func readCounters() -> [String: (rx: UInt32, tx: UInt32)]? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = start
        while let c = cursor {
            let name = String(cString: c.pointee.ifa_name)
            // 只统计活跃的物理接口 (en0 = Wi-Fi, enX = 以太网)，排除 lo0 回环
            if name.hasPrefix("en") || name.hasPrefix("ap"),
               let data = c.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                counters[name] = (data.pointee.ifi_ibytes, data.pointee.ifi_obytes)
            }
            cursor = c.pointee.ifa_next
        }
        return counters
    }

    /// 格式化成可读速度
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec >= 0 else { return "0 KB/s" }
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        }
    }
}
