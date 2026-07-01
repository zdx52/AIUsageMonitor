import Foundation

// MARK: - 网络速度采样

class NetworkSpeedMonitor {
    static let shared = NetworkSpeedMonitor()
    
    private var previousSample: (rx: UInt64, tx: UInt64, time: Date)?
    
    struct Speed {
        let upload: String   // 上传速度，如 "1.2 MB/s" 或 "512 KB/s"
        let download: String // 下载速度，如 "3.5 MB/s"
    }
    
    /// 获取当前网速（每秒调用一次）
    func getSpeed() -> Speed? {
        let current = getTotalBytes()
        guard let current = current else { return nil }
        
        defer { previousSample = (current.rx, current.tx, Date()) }
        
        guard let prev = previousSample else { return nil }
        
        let elapsed = current.time.timeIntervalSince(prev.time)
        guard elapsed > 0 else { return nil }
        
        // 防止网络接口计数器回绕或接口列表变化导致 UInt64 减法溢出崩溃
        let rxDelta: UInt64 = current.rx >= prev.rx ? current.rx - prev.rx : 0
        let txDelta: UInt64 = current.tx >= prev.tx ? current.tx - prev.tx : 0
        let rxSpeed = Double(rxDelta) / elapsed  // bytes/s
        let txSpeed = Double(txDelta) / elapsed  // bytes/s
        
        return Speed(
            upload: formatSpeed(txSpeed),
            download: formatSpeed(rxSpeed)
        )
    }
    
    /// 读取所有活跃物理接口的总收发字节数
    private func getTotalBytes() -> (rx: UInt64, tx: UInt64, time: Date)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let start = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var totalRX: UInt64 = 0
        var totalTX: UInt64 = 0
        
        var cursor = start
        while true {
            let name = String(cString: cursor.pointee.ifa_name)
            // 只统计活跃的物理接口 (en0 = Wi-Fi, enX = 以太网)，排除 lo0 回环
            let isPhysical = name.hasPrefix("en") || name.hasPrefix("ap")
            
            if isPhysical {
                let data = cursor.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
                if let data = data {
                    totalRX += UInt64(data.pointee.ifi_ibytes)
                    totalTX += UInt64(data.pointee.ifi_obytes)
                }
            }
            
            guard let next = cursor.pointee.ifa_next else { break }
            cursor = next
        }
        
        return (totalRX, totalTX, Date())
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
