import SwiftUI
import AppKit

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

class AppDelegate: NSObject, NSApplicationDelegate {
    let dataStore = DataStore()
    var refreshTimer: Timer?
    lazy var statusBarIcon: NSImage = {
        return NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil) ?? NSImage()
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
            Task {
                await self?.dataStore.refreshAll()
            }
        }
    }
    
    @objc func userDefaultsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.setupRefreshTimer()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
