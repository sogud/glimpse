import AppKit

@main
@MainActor
enum GlimpseMacApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = GlimpseApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class GlimpseApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var coordinator: PhotoClassificationCoordinator?
    private var mainWindow: GlimpseMainWindowController?
    private var errorWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
            let container = try PhotoClassificationTaskStore.nativeContainer(
                directory: support.appendingPathComponent("Glimpse/Native", isDirectory: true))
            let coordinator = PhotoClassificationCoordinator(container: container)
            self.coordinator = coordinator
            mainWindow = GlimpseMainWindowController(coordinator: coordinator)
            mainWindow?.showWindow(nil)
            Task { await coordinator.bootstrap() }
        } catch {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 360),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Glimpse"
            window.isReleasedWhenClosed = false
            let content = NativeUI.stack([
                NativeUI.label("无法打开本机任务存储", size: 22, weight: .semibold),
                NativeUI.label(error.localizedDescription),
                NativeUI.label("请检查目录权限和磁盘空间。不会自动删除或重建现有数据库。", color: .secondaryLabelColor)
            ], spacing: 20)
            let root = NSView()
            NativeUI.pin(content, to: root, inset: 28)
            window.contentView = root
            window.center()
            window.makeKeyAndOrderFront(nil)
            errorWindow = window
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "photo.stack", accessibilityDescription: "Glimpse")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await coordinator?.refreshEnvironment() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.activeTaskID != nil || coordinator.tasks.contains(where: { $0.state == .applying }) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "退出 Glimpse？"
        alert.informativeText = "正在进行的分析将暂停。若相册写入或撤销尚未结束，下次启动必须先检查 Photos 中的实际结果。"
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: "退出")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        if let identifier = coordinator.activeTaskID { coordinator.pause(taskID: identifier) }
        return .terminateNow
    }

    private func installMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Glimpse")
        appMenu.addItem(withTitle: "关于 Glimpse", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Glimpse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let new = fileMenu.addItem(withTitle: "新建分类任务", action: #selector(newTask), keyEquivalent: "n")
        new.target = self
        let refresh = fileMenu.addItem(withTitle: "刷新照片和模型状态", action: #selector(refreshEnvironment), keyEquivalent: "r")
        refresh.target = self
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let title: String
        if let coordinator, let identifier = coordinator.activeTaskID,
           let task = coordinator.tasks.first(where: { $0.id == identifier }) {
            title = "\(task.state == .paused ? "正在暂停" : "正在分类") · \(task.progress.analyzed)/\(task.progress.total)"
        } else { title = coordinator == nil ? "任务存储不可用" : "没有运行中的任务" }
        let summary = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        let open = menu.addItem(withTitle: "打开 Glimpse", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        if let coordinator, let identifier = coordinator.activeTaskID,
           coordinator.tasks.first(where: { $0.id == identifier })?.state == .running {
            let pause = menu.addItem(withTitle: "暂停分类", action: #selector(pause), keyEquivalent: "")
            pause.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func openMainWindow() {
        mainWindow?.showWindow(nil)
        errorWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    @objc private func newTask() { mainWindow?.newTask(); openMainWindow() }
    @objc private func refreshEnvironment() { mainWindow?.refreshEnvironment() }
    @objc private func pause() {
        if let identifier = coordinator?.activeTaskID { coordinator?.pause(taskID: identifier) }
    }
}
