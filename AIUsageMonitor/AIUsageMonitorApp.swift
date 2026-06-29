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
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(dataStore)
        )
        
        // 全局事件监听：点击弹窗外部自动关闭
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let popover = self.popover, popover.isShown else { return }
            popover.performClose(nil)
        }
        
        // 每 3 秒更新网速和标题（用颜色表示健康状态）
        titleUpdateTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem?.button else { return }
            let title = self.dataStore.menuBarTitle
            let color: NSColor
            switch self.dataStore.healthLevel {
            case .critical: color = .systemRed
            case .warning:  color = .systemOrange
            case .healthy:  color = .labelColor
            }
            let attr: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            button.attributedTitle = NSAttributedString(string: title, attributes: attr)
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
        
        // 启动时立即获取一次 Hindsight 数据
        Task { @MainActor in
            await dataStore.refreshHindsight()
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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let closePopoverForPanel = Notification.Name("closePopoverForPanel")
}
