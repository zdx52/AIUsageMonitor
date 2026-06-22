import SwiftUI
import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    
    static let shared = SettingsWindowController()
    
    private var hostingView: NSHostingView<AnyView>?
    private var currentDataStore: DataStore?
    
    func show(with dataStore: DataStore) {
        self.currentDataStore = dataStore
        
        DispatchQueue.main.async {
            if self.window == nil {
                let settingsView = SettingsView()
                    .environmentObject(dataStore)
                self.hostingView = NSHostingView(rootView: AnyView(settingsView))
                
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                    styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.title = "设置"
                panel.titlebarAppearsTransparent = true
                panel.isMovableByWindowBackground = true
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
                panel.hasShadow = true
                panel.backgroundColor = .controlBackgroundColor
                panel.contentView = self.hostingView
                panel.delegate = self
                
                self.window = panel
            }
            
            self.window?.center()
            self.window?.orderFrontRegardless()
        }
    }
    
    func windowDidClose(_ notification: Notification) {
        hostingView = nil
        currentDataStore = nil
    }
}
