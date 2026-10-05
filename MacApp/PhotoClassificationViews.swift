import AppKit
import Combine
import Photos

@MainActor
final class GlimpseMainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: PhotoClassificationCoordinator
    private let table = NSTableView()
    private let detail = NSView()
    private let detailHost = NSViewController()
    private var detailController: NSViewController?
    private var shownTaskID: UUID?
    private var rendering = false
    private var subscriptions = Set<AnyCancellable>()
    private var editor: PhotoSchemeEditorWindowController?
    private var refreshButton: NativeButton!
    private var deleteButton: NativeButton!

    init(coordinator: PhotoClassificationCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Glimpse"
        window.minSize = NSSize(width: 980, height: 680)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        buildLayout()
        coordinator.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification, object: window)
            .sink { [weak self] _ in self?.render() }.store(in: &subscriptions)
        render()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit window") }

    func newTask() {
        guard window?.attachedSheet == nil else { return }
        coordinator.isCreatingTask = true
        coordinator.selectedTaskID = nil
        showWindow(nil)
    }

    func refreshEnvironment() { Task { await coordinator.refreshEnvironment() } }

    private func buildLayout() {
        guard let window else { return }
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        let sidebar = NSView()
        let new = NativeButton("新建分类任务") { [weak self] in self?.newTask() }
        new.keyEquivalent = "n"
        new.keyEquivalentModifierMask = .command
        refreshButton = NativeButton("刷新照片和模型状态") { [weak self] in self?.refreshEnvironment() }
        deleteButton = NativeButton("删除所选任务") { [weak self] in self?.deleteSelectedTask() }
        let title = NativeUI.label("分类任务", size: 18, weight: .semibold)
        let toolbar = NativeUI.stack([title, new, refreshButton])
        let column = NSTableColumn(identifier: .init("task"))
        column.resizingMask = .autoresizingMask
        column.width = 240
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 58
        table.dataSource = self
        table.delegate = self
        table.selectionHighlightStyle = .sourceList
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        sidebar.addSubview(toolbar)
        sidebar.addSubview(scroll)
        sidebar.addSubview(deleteButton)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            toolbar.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            toolbar.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -12),
            deleteButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            deleteButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16)
        ])
        let sidebarHost = NSViewController()
        sidebarHost.view = sidebar
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = false
        detailHost.view = detail
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: detailHost))
        window.contentViewController = split
        split.splitView.setPosition(250, ofDividerAt: 0)
    }

    private func render() {
        guard !rendering else { return }
        rendering = true
        defer { rendering = false }
        refreshButton.isEnabled = coordinator.canChangeEnvironment
        deleteButton.isEnabled = coordinator.selectedTaskID.map { coordinator.canDeleteTask(id: $0) } ?? false
        table.reloadData()
        if let index = coordinator.tasks.firstIndex(where: { $0.id == coordinator.selectedTaskID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else { table.deselectAll(nil) }

        let status = coordinator.authorizationStatus
        if status != .authorized && status != .limited {
            showPermission(status)
        } else if coordinator.isCreatingTask || coordinator.selectedTask == nil {
            showNewTask()
        } else if let task = coordinator.selectedTask {
            if task.state == .draft || task.state == .running || task.state == .paused || task.state == .failed {
                showProgress(task)
            } else { showReview(task) }
        }
        if let message = coordinator.errorMessage, window?.attachedSheet == nil, let window {
            coordinator.errorMessage = nil
            let alert = NSAlert()
            alert.messageText = "操作失败"
            alert.informativeText = message
            alert.addButton(withTitle: "知道了")
            alert.beginSheetModal(for: window)
        }
    }

    private func embed(_ controller: NSViewController, taskID: UUID? = nil) {
        detailController?.removeFromParent()
        detailController = controller
        detailHost.addChild(controller)
        shownTaskID = taskID
        for child in detail.subviews { child.removeFromSuperview() }
        NativeUI.pin(controller.view, to: detail)
    }

    private func showPermission(_ status: PHAuthorizationStatus) {
        let button = NativeButton(status == .notDetermined ? "授权访问" : "打开系统设置") { [weak self] in
            if status == .notDetermined { Task { await self?.coordinator.requestPhotosPermission() } }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
        }
        let content = NativeUI.stack([
            NativeUI.label("需要 Apple Photos 权限", size: 24, weight: .semibold),
            NativeUI.label("图片只交给本机模型识别。分析不会修改 Photos，复核并确认后才加入相册。iCloud 照片可能需要系统下载。"), button,
            NativeUI.label("若已拒绝，在“隐私与安全性 → 照片”中允许 Glimpse 访问，再回来刷新。", size: 12, color: .secondaryLabelColor)
        ], spacing: 20)
        content.edgeInsets = NSEdgeInsets(top: 32, left: 28, bottom: 28, right: 28)
        let controller = NSViewController()
        controller.view = NativeUI.scroll(content)
        embed(controller)
    }

    private func showNewTask() {
        let controller: NewTaskViewController
        if let current = detailController as? NewTaskViewController { controller = current }
        else {
            controller = NewTaskViewController { [weak self] action in self?.handleNewTask(action) }
            embed(controller)
        }
        controller.update(count: coordinator.accessiblePhotoCount, limited: coordinator.authorizationStatus == .limited,
                          albums: coordinator.albums, connection: coordinator.modelConnection, endpoint: coordinator.endpointText,
                          preferredModel: coordinator.preferredModelIdentifier, isBusy: !coordinator.canChangeEnvironment)
    }

    private func handleNewTask(_ action: NewTaskAction) {
        switch action {
        case .create(let source, let title, let model, let limit):
            Task {
                _ = await coordinator.createTask(source: source, title: title, modelIdentifier: model,
                                                 ordinaryScheme: coordinator.savedOrdinaryScheme,
                                                 screenshotScheme: coordinator.savedScreenshotScheme, limit: limit)
            }
        case .endpointChanged(let endpoint):
            coordinator.endpointText = endpoint
            coordinator.updateEndpoint()
        case .refresh: refreshEnvironment()
        case .editScheme(let kind):
            editor = PhotoSchemeEditorWindowController(coordinator: coordinator, kind: kind)
            editor?.showWindow(nil)
        }
    }

    private func showProgress(_ task: PhotoClassificationTask) {
        let progress = task.progress
        let indicator = NSProgressIndicator()
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = Double(max(progress.total, 1))
        indicator.doubleValue = Double(progress.analyzed)
        indicator.widthAnchor.constraint(equalToConstant: 500).isActive = true
        let start = NativeButton(task.state == .draft ? "开始分类" : "继续分类") { [weak self] in
            self?.coordinator.startOrContinue(taskID: task.id)
        }
        start.isEnabled = task.state.canStartOrContinueInference && coordinator.canChangeEnvironment
        let pause = NativeButton("暂停分类") { [weak self] in self?.coordinator.pause(taskID: task.id) }
        pause.isEnabled = task.state == .running
        let isPausing = task.state == .paused && coordinator.activeTaskID == task.id
        let content = NativeUI.stack([
            NativeUI.label(task.title, size: 24, weight: .semibold),
            NativeUI.label(isPausing ? "正在暂停，等待当前请求退出…" : task.state.localizedTitle, color: .controlAccentColor), indicator,
            NativeUI.label("本批 \(progress.total) 张 · 已分析 \(progress.analyzed) · 已分类 \(progress.classified) · 待分类 \(progress.needsReview) · 未分析 \(progress.remaining)"),
            NativeUI.label("图片逐张串行发送到本机模型。分析只保存结果，不会改动相册。", size: 12, color: .secondaryLabelColor),
            NativeUI.stack([start, pause], horizontal: true)
        ], spacing: 20)
        content.edgeInsets = NSEdgeInsets(top: 28, left: 24, bottom: 24, right: 24)
        let controller = NSViewController()
        controller.view = NativeUI.scroll(content)
        embed(controller, taskID: task.id)
    }

    private func showReview(_ task: PhotoClassificationTask) {
        if let current = detailController as? PhotoReviewViewController, shownTaskID == task.id {
            current.update(task: task, albums: coordinator.albums, isBusy: !coordinator.canChangeEnvironment)
            return
        }
        let controller = PhotoReviewViewController(task: task, albums: coordinator.albums,
                                                  thumbnail: { [weak coordinator] identifier, edge in
            await coordinator?.thumbnail(assetIdentifier: identifier, longestEdge: edge)
        }, onAction: { [weak self] action in self?.handleReview(action, taskID: task.id) })
        embed(controller, taskID: task.id)
        controller.update(task: task, albums: coordinator.albums, isBusy: !coordinator.canChangeEnvironment)
    }

    private func handleReview(_ action: PhotoReviewAction, taskID: UUID) {
        switch action {
        case .categoryChanged(let identifier, let category):
            coordinator.updateCategory(taskID: taskID, assetIdentifier: identifier, categoryIdentifier: category)
        case .approvalChanged(let identifier, let approved):
            coordinator.setApproved(taskID: taskID, assetIdentifier: identifier, approved: approved)
        case .apply(let confirmation): Task { await coordinator.apply(confirmation) }
        case .targetChanged(let category, let target): coordinator.setTarget(taskID: taskID, categoryIdentifier: category, target: target)
        case .undo(let deleteEmpty): Task { await coordinator.undo(taskID: taskID, deleteEmptyCreatedAlbums: deleteEmpty) }
        case .acknowledgeInterruption: coordinator.acknowledgeInterruptedWrite(taskID: taskID)
        case .recheck: coordinator.startOrContinue(taskID: taskID)
        }
    }

    private func deleteSelectedTask() {
        guard let task = coordinator.selectedTask, coordinator.canDeleteTask(id: task.id), let window else { return }
        let alert = NSAlert()
        alert.messageText = "删除任务？"
        alert.informativeText = task.state == .applied ? "将失去本次整理的撤销记录，不会修改 Photos。" : "删除进度和分类结果，不会修改 Photos。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "删除任务")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.coordinator.deleteTask(id: task.id) }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { coordinator.tasks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let task = coordinator.tasks[row]
        let title = NativeUI.label(task.title, weight: .medium)
        title.maximumNumberOfLines = 1
        let status = NativeUI.label("\(task.progress.analyzed)/\(task.progress.total) · \(task.state.localizedTitle)", size: 11, color: .secondaryLabelColor)
        let cell = NSTableCellView()
        NativeUI.pin(NativeUI.stack([title, status], spacing: 4), to: cell, inset: 8)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rendering, coordinator.tasks.indices.contains(table.selectedRow) else { return }
        coordinator.isCreatingTask = false
        coordinator.selectedTaskID = coordinator.tasks[table.selectedRow].id
    }
}
