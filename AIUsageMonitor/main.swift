import AppKit

// AppKit 入口：故意不使用 SwiftUI 的 App 生命周期。
// 原因是 SwiftUI 的 Settings 场景是该 app 唯一的场景时，macOS 会在启动时自动把它弹出来，
// 而本 app 的设置窗口是 SettingsWindowController 里的 NSPanel（Settings 场景只是占位）→ 启动即出现空白"设置"窗口。
// NSApplication.delegate 是 weak，必须用全局变量持有 delegate。
private var appDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}
