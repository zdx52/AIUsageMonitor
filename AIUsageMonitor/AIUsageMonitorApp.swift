import SwiftUI
import AppKit
import Combine

// 入口在 main.swift（AppKit NSApplication），这里只放 AppDelegate。
// 不要改回 @main + Settings 场景：那会让 macOS 启动时自动弹出空白"设置"窗口。
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
    /// 上次写进菜单栏的内容指纹，内容没变就跳过重绘（省每秒一次的 CoreGraphics 文字渲染）
    private var lastTitleKey = ""
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
        
        setupNetworkSpeedTimer()
        
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
        
        // 监听看板/小说窗口可见性变化，刷新 Dock 图标（窗口开 → 显示，全关 → 消失）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowVisibilityChanged),
            name: .windowVisibilityChanged,
            object: nil
        )
        // 窗口真正关闭后也会触发（willClose 通知发出时 isVisible 已为 false）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowVisibilityChanged),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        
        // .regular 激活策略下的最小菜单栏（App 菜单 + 窗口菜单，窗口菜单自动列窗口便于来回切换）
        setupMainMenu()
        
        Task {
            await dataStore.refreshAll()
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
    
    /// 窗口可见性变化（延迟一帧，等窗口真正关闭后再判断）
    @objc func handleWindowVisibilityChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateDockPresence()
        }
    }
    
    /// 看板/小说窗口任一可见 → Dock 显示图标（.regular）；全部关闭 → 图标消失（.accessory）
    func updateDockPresence() {
        let dashboardVisible = DashboardWindowController.shared.window?.isVisible ?? false
        let novelVisible = NovelWebWindowController.shared.window?.isVisible ?? false
        let douyinVisible = DouyinWindowController.shared.window?.isVisible ?? false
        let target: NSApplication.ActivationPolicy = (dashboardVisible || novelVisible || douyinVisible) ? .regular : .accessory
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
            print("🖥️ Dock 呈现切换: \(target == .regular ? "显示图标" : "隐藏图标")")
        }
    }
    
    /// 关闭最后一个窗口不退出应用（菜单栏监控常驻）
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    /// 设置 .regular 状态下的最小菜单栏（App 菜单 + 编辑菜单 + 窗口菜单）
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 AIUsageMonitor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 AIUsageMonitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        
        // 编辑菜单：AppKit 的 ⌘V / ⌘C / ⌘A 是走菜单项的 keyEquivalent 的，
        // 没有这个菜单，输入框里按 ⌘V 什么都不会发生（只能右键粘贴）。
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        // AppKit 自动把打开的窗口列进窗口菜单，方便在看板/小说间切换
        NSApp.windowsMenu = windowMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    /// 按设置（1/2/3/5 秒）重建网速采样和菜单栏重绘的 Timer
    func setupNetworkSpeedTimer() {
        networkSpeedTimer?.invalidate()
        titleUpdateTimer?.invalidate()

        let saved = UserDefaults.standard.object(forKey: "networkSpeedInterval") as? Double ?? 1
        let interval = min(max(saved, 1), 10)

        networkSpeedTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dataStore.updateNetworkSpeed()
            }
        }
        // .common：点菜单/弹窗交互期间也照常采样
        RunLoop.main.add(networkSpeedTimer!, forMode: .common)

        titleUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshMenuBarTitle()
            }
        }
        RunLoop.main.add(titleUpdateTimer!, forMode: .common)
    }

    /// 重绘菜单栏标题（温度计按温度变色，其余文字保持默认色）
    func refreshMenuBarTitle() {
        guard let button = statusItem?.button else { return }

        // 内容没变就不重绘（网速稳定/空闲时省掉一次文字渲染）
        let key = "\(dataStore.menuBarTitle)|\(dataStore.temperatureData?.thermalState.rawValue ?? -1)|\(dataStore.temperatureData?.cpuTemperature ?? 0)|\(dataStore.temperatureData?.batteryTemperature ?? 0)"
        guard key != lastTitleKey else { return }
        lastTitleKey = key

        let attrString = NSMutableAttributedString()

        // 竖直温度计 SF Symbol（按温度变色）
        if let td = dataStore.temperatureData {
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
        let restString = NSAttributedString(string: dataStore.menuBarTitle, attributes: [.foregroundColor: NSColor.labelColor])
        attrString.append(restString)

        button.attributedTitle = attrString
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
        setupNetworkSpeedTimer()
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
        NovelWebServer.shutdown()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let closePopoverForPanel = Notification.Name("closePopoverForPanel")
    static let windowVisibilityChanged = Notification.Name("windowVisibilityChanged")
}
