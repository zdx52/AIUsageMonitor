import SwiftUI
import AppKit
import Combine

@main
struct AIUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.dataStore)
        } label: {
            Label {
                Text(appDelegate.dataStore.menuBarTitle)
            } icon: {
                Image(nsImage: appDelegate.statusBarIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let dataStore = DataStore()
    var cancellables = Set<AnyCancellable>()
    var refreshTimer: Timer?
    lazy var statusBarIcon: NSImage = {
        let img = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupRefreshTimer()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        
        // 订阅健康度变化，动态更新图标颜色
        dataStore.$healthLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.updateStatusBarIcon(health: level)
            }
            .store(in: &cancellables)
        
        Task {
            await dataStore.refreshAll()
        }
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
    }
    
    func updateStatusBarIcon(health: ServiceHealth) {
        guard let img = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil) else {
            return
        }
        
        switch health {
        case .critical:
            guard let colored = img.withSymbolConfiguration(.init(paletteColors: [.systemRed])) else { return }
            statusBarIcon = colored
        case .warning:
            guard let colored = img.withSymbolConfiguration(.init(paletteColors: [.systemOrange])) else { return }
            statusBarIcon = colored
        case .healthy:
            // 使用模板图标，系统自动适配浅色/深色菜单栏
            img.isTemplate = true
            statusBarIcon = img
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
