import SwiftUI
import AppKit

/// 抖音下载窗口：粘链接 → 下载 → 存到「下载」文件夹
struct DouyinDownloadView: View {

    @State private var link = ""
    @State private var status = "把作品链接或分享文案整条粘进来"
    @State private var busy = false
    @State private var history: [String] = []
    @FocusState private var linkFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("抖音视频下载")
                .font(.headline)

            TextField("https://www.douyin.com/video/… 或 v.douyin.com 短链 或分享文案", text: $link)
                .textFieldStyle(.roundedBorder)
                .disabled(busy)
                .focused($linkFocused)
                .onSubmit(start)
                .font(.system(size: 12, design: .monospaced))

            HStack(spacing: 10) {
                Button(action: start) {
                    Label(busy ? "下载中…" : "下载", systemImage: "arrow.down.circle")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("打开下载目录") {
                    NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
                }
                .font(.caption)

                Spacer()
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(busy ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !history.isEmpty {
                Divider()
                Text("已下载")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(history, id: \.self) { item in
                    Text(item)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text("取的是作品页里最高一档源（通常是 4K），比网页播放器给你的清晰。只支持单条视频。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // 窗口打开就把光标放进输入框，⌘V 直接可用
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { linkFocused = true }
        }
    }

    private func start() {
        guard !busy else { return }
        busy = true
        status = "正在解析…"
        DouyinDownloader.shared.download(link: link) { message in
            status = message
        } completion: { result in
            busy = false
            switch result {
            case .success(let url):
                status = "✅ 已保存：\(url.lastPathComponent)"
                history.insert(url.lastPathComponent, at: 0)
                if history.count > 5 { history.removeLast() }
                link = ""
            case .failure(let error):
                status = "❌ \(error.localizedDescription)"
            }
        }
    }
}

/// 抖音下载窗口控制器（原生窗口，不依赖本地 Web 服务）
class DouyinWindowController: NSWindowController, NSWindowDelegate {

    static let shared = DouyinWindowController()

    func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: DouyinDownloadView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "抖音下载"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        window.contentView = hosting
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .windowVisibilityChanged, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .windowVisibilityChanged, object: nil)
    }
}
