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
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task {
                await self?.dataStore.refreshAll()
            }
        }
        
        Task {
            await dataStore.refreshAll()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }
}
