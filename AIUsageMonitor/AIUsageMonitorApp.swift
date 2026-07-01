import SwiftUI
import AppKit
import Combine

@main
struct AIUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 用 Settings 场景提供设置窗口，菜单栏由 AppDelegate 用 NSStatusItem 管理
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let dataStore = DataStore()
    var cancellables = Set<AnyCancellable>()
    var refreshTimer: Timer?
    var networkSpeedTimer: Timer?
    var titleUpdateTimer: Timer?
    var hindsightTimer: Timer?
    var temperatureTimer: Timer?
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: Any?
    lazy var statusBarIcon: NSImage = {
        let img = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // 创建 NSStatusItem
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "⏳"
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // 创建弹出面板
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 500, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(dataStore)
        )
        
        // 全局事件监听：点击弹窗外部自动关闭
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let popover = self.popover, popover.isShown else { return }
            popover.performClose(nil)
        }
        
        // 每 3 秒更新标题（温度计按温度变色，其余文字保持默认色）
        titleUpdateTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem?.button else { return }
            
            let attrString = NSMutableAttributedString()
            
            // 竖直温度计 SF Symbol（按温度变色）
            if let td = self.dataStore.temperatureData {
                let img = NSImage(systemSymbolName: "thermometer", accessibilityDescription: nil) ?? NSImage()
                let attachment = NSTextAttachment()
                attachment.image = img
                attachment.bounds = CGRect(x: 0, y: -3, width: 11, height: 17)
                attrString.append(NSAttributedString(attachment: attachment))
                attrString.append(NSAttributedString(string: " "))
                
                let thermoColor: NSColor
                switch td.thermalState {
                case .critical, .serious: thermoColor = .systemRed
                case .fair:               thermoColor = .systemOrange
                case .nominal:            thermoColor = .systemGreen
                @unknown default:         thermoColor = .labelColor
                }
                attrString.addAttribute(.foregroundColor, value: thermoColor, range: NSRange(location: 0, length: 1))
            }
            
            // 其余文字（温度值 + CPU + 网速）保持默认色
            let restString = NSAttributedString(string: self.dataStore.menuBarTitle, attributes: [.foregroundColor: NSColor.labelColor])
            attrString.append(restString)
            
            button.attributedTitle = attrString
        }
        
        setupRefreshTimer()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        
        dataStore.$healthLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.updateStatusBarIcon(health: level)
            }
            .store(in: &cancellables)
        
        // 监听弹窗关闭通知（设置/看板按钮发出）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopover),
            name: .closePopoverForPanel,
            object: nil
        )
        
        Task {
            await dataStore.refreshAll()
        }
        
        networkSpeedTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dataStore.updateNetworkSpeed()
            }
        }
        
        // Hindsight 跟随用户设置的刷新间隔
        setupHindsightTimer()
        
        // 每 3 秒刷新温度
        temperatureTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.dataStore.refreshTemperature()
        }
        RunLoop.main.add(temperatureTimer!, forMode: .common)
        
        // 启动时立即获取一次温度
        dataStore.refreshTemperature()
        
        // 启动时持续重试直到 Hindsight 就绪（每 3 秒一次，最多等 2 分钟）
        Task { @MainActor in
            var attempts = 0
            let maxAttempts = 40
            while attempts < maxAttempts {
                await dataStore.refreshHindsight()
                if dataStore.hindsightAvailable { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                attempts += 1
            }
        }
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc func closePopover() {
        popover?.close()
    }
    
    func setupRefreshTimer() {
        refreshTimer?.invalidate()
        
        let interval: TimeInterval
        if let saved = UserDefaults.standard.object(forKey: "refreshInterval") as? Double, saved >= 60 {
            interval = saved
        } else {
            interval = 300
        }
        
        print("⏱️ 设置刷新间隔: \(Int(interval / 60)) 分钟")
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.dataStore.refreshAll()
            }
        }
        // 添加到 .common mode，确保菜单弹出时（.eventTracking）Timer 也能触发
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
    
    @objc func userDefaultsDidChange() {
        setupRefreshTimer()
        setupHindsightTimer()
    }
    
    func setupHindsightTimer() {
        hindsightTimer?.invalidate()
        let interval: TimeInterval
        if let saved = UserDefaults.standard.object(forKey: "refreshInterval") as? Double, saved >= 60 {
            interval = saved
        } else {
            interval = 300
        }
        hindsightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.dataStore.refreshHindsight()
            }
        }
        RunLoop.main.add(hindsightTimer!, forMode: .common)
    }
    
    func updateStatusBarIcon(health: ServiceHealth) {
        // 图标和颜色已移至弹窗内显示，菜单栏只显示网速
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        networkSpeedTimer?.invalidate()
        titleUpdateTimer?.invalidate()
        hindsightTimer?.invalidate()
        temperatureTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let closePopoverForPanel = Notification.Name("closePopoverForPanel")
}
