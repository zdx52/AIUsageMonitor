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
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
        return img.withSymbolConfiguration(config) ?? img
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
    }
    
    @objc func userDefaultsDidChange() {
        setupRefreshTimer()
    }
    
    func updateStatusBarIcon(health: ServiceHealth) {
        let color: NSColor
        switch health {
        case .critical:
            color = .systemRed
        case .warning:
            color = .systemOrange
        case .healthy:
            color = .systemGreen
        }
        
        guard let img = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil),
              let colored = img.withSymbolConfiguration(.init(paletteColors: [color])) else {
            return
        }
        statusBarIcon = colored
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
