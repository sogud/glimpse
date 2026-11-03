import AppKit

enum PhotoReviewAction {
    case categoryChanged(assetIdentifier: String, categoryIdentifier: PhotoClassificationCategoryID?)
    case approvalChanged(assetIdentifier: String, approved: Bool)
    case targetChanged(categoryIdentifier: PhotoClassificationCategoryID, target: PhotoAlbumTarget)
    case undo(deleteEmptyCreatedAlbums: Bool)
    case acknowledgeInterruption
    case recheck
    case apply(PhotoClassificationWriteConfirmation)
}

@MainActor
final class PhotoReviewViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private var task: PhotoClassificationTask
    private var albums: [PhotoAlbumDescriptor]
    private let thumbnail: (String, CGFloat) async -> NSImage?
    private let onAction: (PhotoReviewAction) -> Void
    private let heading = NativeUI.label("", size: 26, weight: .semibold, color: NativeUI.ink)
    private let summary = NativeUI.label("", size: 12, color: NativeUI.muted)
    private let nextStep = NativeUI.label("", size: 12, color: NativeUI.muted)
    private let steps = NativeUI.steps(current: 2)
    private let empty = NativeUI.label("暂无分类结果", size: 16, color: NativeUI.muted)
    private let collection = NSCollectionView()
    private var isBusy = false
    private var writeButton: NativeButton!
    private var undoButton: NativeButton!
    private var acknowledgeButton: NativeButton!
    private var recheckButton: NativeButton!
    private var mappingButton: NativeButton!
    private var mappingWindow: NSWindow?
    private var inspector: PhotoInspectorWindowController?
    private let filter = NativePopUpButton()
    private let bulk = NativePopUpButton()
    private var tools: NSStackView!
    private var visibleIndices: [Int] = []
    private var filterIdentifiers: [PhotoClassificationCategoryID?] = []
    private var selectedFilter = 0

    init(task: PhotoClassificationTask, albums: [PhotoAlbumDescriptor],
         thumbnail: @escaping (String, CGFloat) async -> NSImage?, onAction: @escaping (PhotoReviewAction) -> Void) {
        self.task = task
        self.albums = albums
        self.thumbnail = thumbnail
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit view") }

    override func loadView() {
        let root = NativeSurfaceView(frame: NSRect(x: 0, y: 0, width: 850, height: 650))
        writeButton = NativeButton("预览加入相册…") { [weak self] in self?.confirmWrite() }
        writeButton.setAccessibilityIdentifier("preview-albums")
        writeButton.keyEquivalent = "\r"
        NativeUI.primary(writeButton)
        undoButton = NativeButton("撤销本次整理") { [weak self] in self?.confirmUndo() }
        acknowledgeButton = NativeButton("已检查，关闭任务") { [weak self] in self?.onAction(.acknowledgeInterruption) }
        recheckButton = NativeButton("重新检查") { [weak self] in self?.onAction(.recheck) }
        mappingButton = NativeButton("选择目标相册") { [weak self] in self?.showMapping() }
        filter.onSelection = { [weak self] index in
            self?.selectedFilter = index
            self?.reloadPhotos()
        }
        bulk.onSelection = { [weak self] index in
            if index == 1 { self?.setVisibleApproval(true) }
            else if index == 2 { self?.setVisibleApproval(false) }
            else if index >= 4 { self?.moveSelection(index) }
            self?.bulk.selectItem(at: 0)
        }
        filter.setAccessibilityLabel("筛选照片分类")
        bulk.setAccessibilityLabel("批量勾选与改类")
        filter.widthAnchor.constraint(equalToConstant: 180).isActive = true
        bulk.widthAnchor.constraint(equalToConstant: 180).isActive = true
        bulk.toolTip = "点图片选中，按住 ⌘ 多选后改类。“加入相册”勾选单独决定写入。"
        let selectionTools = NativeUI.stack([filter, bulk], horizontal: true, spacing: 12)
        let secondaryTools = NativeUI.stack([mappingButton, recheckButton], horizontal: true, spacing: 12)
        mappingButton.bezelStyle = .inline
        recheckButton.bezelStyle = .inline
        tools = NativeUI.stack([selectionTools, secondaryTools], horizontal: true, spacing: 16)
        tools.setHuggingPriority(.required, for: .vertical)
        for control in [filter, bulk, mappingButton, recheckButton] as [NSControl] {
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        }
        let header = NativeUI.stack([heading, steps, summary, tools], spacing: 12)
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 220, height: 368)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        collection.collectionViewLayout = layout
        collection.frame = NSRect(x: 0, y: 0, width: 800, height: 450)
        collection.autoresizingMask = [.width]
        collection.backgroundColors = [NativeUI.canvas]
        collection.register(PhotoReviewItem.self, forItemWithIdentifier: .init("photo"))
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = collection
        let footer = NativeUI.commandBar(message: nextStep, actions: NativeUI.stack([writeButton, undoButton, acknowledgeButton], horizontal: true))
        let line = NativeUI.separator()
        for child in [header, scroll, empty, line, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            summary.widthAnchor.constraint(equalTo: header.widthAnchor),
            tools.widthAnchor.constraint(equalTo: header.widthAnchor),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -16),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        view = root
        root.layoutSubtreeIfNeeded()
        render()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let compactTools = view.bounds.width < 760
        let orientation: NSUserInterfaceLayoutOrientation = compactTools ? .vertical : .horizontal
        if tools.orientation != orientation {
            tools.orientation = orientation
            tools.alignment = compactTools ? .leading : .centerY
            tools.spacing = compactTools ? 4 : 16
        }
        guard let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        let available = collection.enclosingScrollView?.contentSize.width ?? collection.bounds.width
        let columns = max(1, Int((available + 16) / 236))
        let width = floor((available - CGFloat(columns - 1) * 16) / CGFloat(columns))
        if abs(layout.itemSize.width - width) > 0.5 {
            layout.itemSize = NSSize(width: width, height: 368)
            layout.invalidateLayout()
        }
    }

    func update(task: PhotoClassificationTask, albums: [PhotoAlbumDescriptor], isBusy: Bool = false) {
        self.task = task
        self.albums = albums
        self.isBusy = isBusy
        if isViewLoaded { render() }
        inspector?.update(task: task)
    }

    private func render() {
        NativeUI.updateSteps(steps, current: task.state == .readyForReview ? 2 : 3)
        let progress = task.progress
        heading.stringValue = task.state == .readyForReview ? "检查分类结果" : task.state.localizedTitle
        summary.stringValue = "\(task.title) · 已分类 \(progress.classified) 张 · 待分类 \(progress.needsReview) 张"
        let confirmation = task.writeConfirmation
        if isBusy { nextStep.stringValue = "正在处理，请等待当前操作完成。" }
        else if task.state == .readyForReview {
            if task.results.isEmpty {
                nextStep.stringValue = "这批没有分类结果。\n可以“重新检查”，或从左侧开始新的一批。"
            } else if let confirmation {
                nextStep.stringValue = "\(confirmation.additions.count) 张照片将加入 \(confirmation.albumCounts.count) 个相册。\n先预览清单，再确认；不会删除照片。"
            } else { nextStep.stringValue = "先检查分类并勾选照片。\n选择目标相册后，就能预览加入清单。" }
        } else if task.state == .interrupted {
            summary.stringValue = "上次相册操作中断，结果尚未确认。请先在 Apple Photos 检查实际相册。"
            nextStep.stringValue = "这批不能重写或撤销。\n检查实际相册后，再关闭任务。"
        } else if task.state == .applied {
            nextStep.stringValue = "已记录 \(task.mutations.count) 条新增相册归属，原有归属和照片不变。\n继续整理，请点左侧“开始新的一批”。"
        } else if task.state == .applying {
            nextStep.stringValue = "正在等待 Photos 完成操作。\n未确认的变更不会计为成功。"
        } else { nextStep.stringValue = "这批已关闭，分类结果仅供查看。\n可以从侧栏开始新的一批。" }
        writeButton.isHidden = task.state != .readyForReview
        writeButton.isEnabled = !isBusy && task.writeConfirmation != nil
        NativeUI.primaryTitle(writeButton, title: "预览加入相册…")
        undoButton.isHidden = task.state != .applied
        undoButton.isEnabled = !isBusy && !task.mutations.isEmpty
        acknowledgeButton.isHidden = task.state != .interrupted
        acknowledgeButton.isEnabled = !isBusy
        recheckButton.isHidden = !task.state.canReview
        recheckButton.isEnabled = !isBusy
        mappingButton.isEnabled = !isBusy && !categoryEntries.isEmpty
        let previous = selectedFilter
        filterIdentifiers = [nil, nil] + categoryEntries.map { Optional($0.1.id) }
        filter.removeAllItems()
        filter.addItems(withTitles: ["所有照片（\(task.results.count)）", "待分类（\(progress.needsReview)）"] + categoryEntries.map { "\($0.0.name) · \($0.1.name)" })
        selectedFilter = min(previous, filter.numberOfItems - 1)
        filter.selectItem(at: selectedFilter)
        bulk.removeAllItems()
        bulk.addItems(withTitles: ["批量勾选与改类", "勾选筛选结果", "取消筛选结果勾选"])
        bulk.menu?.addItem(.separator())
        bulk.addItems(withTitles: ["所选照片 → 待分类"] + categoryEntries.map { "所选照片 → \($0.0.name) · \($0.1.name)" })
        bulk.menu?.autoenablesItems = false
        collection.isSelectable = task.state.canReview && !isBusy
        reloadPhotos()
    }

    private var categoryEntries: [(PhotoClassificationScheme, PhotoClassificationCategory)] {
        var entries: [(PhotoClassificationScheme, PhotoClassificationCategory)] = []
        for scheme in [task.ordinaryScheme, task.screenshotScheme] {
            for category in scheme.categories where category.isEnabled { entries.append((scheme, category)) }
        }
        return entries
    }

    private func reloadPhotos() {
        visibleIndices = task.results.indices.filter { index in
            if selectedFilter == 0 { return true }
            return task.results[index].effectiveCategoryIdentifier == filterIdentifiers[selectedFilter]
        }
        empty.stringValue = task.results.isEmpty ? "暂无分类结果" : "这个分类暂无照片"
        empty.isHidden = !visibleIndices.isEmpty
        collection.selectionIndexPaths = []
        collection.reloadData()
        updateBulkAvailability()
    }

    private func setVisibleApproval(_ approved: Bool) {
        guard task.state.canReview, !isBusy else { return }
        let results = visibleIndices.map { task.results[$0] }
        for result in results {
            if approved && result.effectiveCategoryIdentifier == nil { continue }
            onAction(.approvalChanged(assetIdentifier: result.id, approved: approved))
        }
    }

    private func updateBulkAvailability() {
        bulk.isEnabled = task.state.canReview && !isBusy && !visibleIndices.isEmpty
        let hasSelection = bulk.isEnabled && !collection.selectionIndexPaths.isEmpty
        bulk.item(at: 0)?.title = hasSelection ? "\(collection.selectionIndexPaths.count) 张已选 · 批量改类" : "批量勾选与改类"
        let selected = collection.selectionIndexPaths.map { task.results[visibleIndices[$0.item]] }
        for index in 4..<bulk.numberOfItems {
            var isCompatible = hasSelection
            if index > 4 {
                let category = categoryEntries[index - 5].1.id
                for result in selected {
                    if task.scheme(for: result)?.categories.contains(where: { $0.id == category && $0.isEnabled }) != true {
                        isCompatible = false
                        break
                    }
                }
            }
            bulk.item(at: index)?.isEnabled = isCompatible
        }
    }

    private func confirmWrite() {
        guard !isBusy, let confirmation = task.writeConfirmation, let parent = view.window,
              parent.attachedSheet == nil else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "加入相册前确认"
        sheet.isReleasedWhenClosed = false
        let header = NativeUI.stack([
            NativeUI.label("加入这些相册？", size: 26, weight: .semibold, color: NativeUI.ink),
            NativeUI.steps(current: 3),
            NativeUI.label("\(confirmation.additions.count) 张照片 · \(confirmation.albumCounts.count) 个相册\n只增加相册归属，照片仍保留在原处。“待删除”仍需人工检查。", color: NativeUI.muted)
        ], spacing: 12)
        var rows: [NSView] = []
        for (target, count) in confirmation.albumCounts.sorted(by: { $0.key.titleForDisplay < $1.key.titleForDisplay }) {
            let name = NativeUI.label(target.titleForDisplay, weight: .medium, color: NativeUI.ink)
            let kind: String
            if case .newAlbum = target { kind = "新建相册" } else { kind = "已有相册" }
            let title = NativeUI.stack([name, NativeUI.label(kind, size: 12, color: NativeUI.muted)], spacing: 4)
            let amount = NativeUI.label("\(count) 张", weight: .medium, color: NativeUI.ink)
            amount.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            amount.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let row = NativeUI.stack([title, amount], horizontal: true, spacing: 24)
            title.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -84).isActive = true
            name.widthAnchor.constraint(equalTo: title.widthAnchor).isActive = true
            rows += [row, NativeUI.separator()]
        }
        let body = NativeUI.stack(rows, spacing: 12)
        for row in rows { row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        let cancel = NativeButton("取消") { [weak parent, weak sheet] in
            if let sheet { parent?.endSheet(sheet, returnCode: .cancel) }
        }
        cancel.keyEquivalent = "\u{1b}"
        let join = NativeButton("加入 \(confirmation.additions.count) 张照片") { [weak parent, weak sheet] in
            if let sheet { parent?.endSheet(sheet, returnCode: .OK) }
        }
        join.setAccessibilityIdentifier("confirm-album-write")
        join.keyEquivalent = "\r"
        NativeUI.primary(join)
        let footer = NativeUI.commandBar(message: NativeUI.label("不删除照片，也不移除原有归属。", size: 12, color: NativeUI.muted),
                                         actions: NativeUI.stack([cancel, join], horizontal: true))
        sheet.contentView = NativeUI.sheet(header: header, body: body, footer: footer)
        parent.beginSheet(sheet) { [weak self] response in
            if response == .OK { self?.onAction(.apply(confirmation)) }
        }
    }

    private func confirmUndo() {
        guard !isBusy, task.state == .applied, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "撤销本次整理？"
        alert.informativeText = "只移除本任务记录为新增的相册归属，不删除照片。删除本次创建的空相册需要单独选择。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "撤销并保留空相册")
        alert.addButton(withTitle: "撤销并删除本次创建的空相册")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.onAction(.undo(deleteEmptyCreatedAlbums: false)) }
            if response == .alertThirdButtonReturn { self?.onAction(.undo(deleteEmptyCreatedAlbums: true)) }
        }
    }

    private func showMapping() {
        guard let parent = view.window, parent.attachedSheet == nil else { return }
        func categoryRows(_ entries: [(PhotoClassificationScheme, PhotoClassificationCategory)]) -> NSStackView {
            var rows: [NSView] = []
            var group: UUID?
            for (scheme, category) in entries {
                if group != scheme.id {
                    rows.append(NativeUI.label(scheme.name, size: 16, weight: .semibold, color: NativeUI.ink))
                    group = scheme.id
                }
                let popup = NativePopUpButton()
                let name = PhotoClassificationPlanner.albumName(schemeName: scheme.name, category: category)
                var targets = [PhotoAlbumTarget.newAlbum(name: name)]
                var titles = ["新建：\(name)"]
                for album in albums {
                    targets.append(.existingAlbum(identifier: album.id, name: album.name))
                    titles.append("已有：\(album.name)（\(album.assetCount) 张 · \(album.id.prefix(8))）")
                }
                targets.append(.skip)
                titles.append("本次跳过")
                let current = task.targetsByCategory[category.id] ?? .skip
                if !targets.contains(current) {
                    targets.insert(current, at: 0)
                    titles.insert("当前目标：\(current.titleForDisplay)", at: 0)
                }
                popup.addItems(withTitles: titles)
                popup.selectItem(at: targets.firstIndex(of: current) ?? 0)
                popup.isEnabled = task.state.canReview && !isBusy
                popup.setAccessibilityLabel("\(scheme.name) · \(category.name)的目标相册")
                popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                popup.onSelection = { [weak self] index in
                    guard self?.task.state.canReview == true, self?.isBusy == false else { return }
                    self?.onAction(.targetChanged(categoryIdentifier: category.id, target: targets[index]))
                }
                let count = task.results.filter { $0.effectiveCategoryIdentifier == category.id }.count
                let label = NativeUI.stack([NativeUI.label(category.name, color: NativeUI.ink),
                                            NativeUI.label("\(count) 张照片", size: 12, color: NativeUI.muted)], spacing: 4)
                label.widthAnchor.constraint(equalToConstant: 170).isActive = true
                let row = NativeUI.stack([label, popup], horizontal: true, spacing: 24)
                popup.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -194).isActive = true
                popup.heightAnchor.constraint(equalToConstant: 40).isActive = true
                rows.append(row)
            }
            let body = NativeUI.stack(rows, spacing: 12)
            for row in rows { row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
            return body
        }
        let populated = categoryEntries.filter { entry in task.results.contains { $0.effectiveCategoryIdentifier == entry.1.id } }
        let others = categoryEntries.filter { entry in !populated.contains { $0.1.id == entry.1.id } }
        var rows: [NSView] = [categoryRows(populated.isEmpty ? categoryEntries : populated)]
        if !populated.isEmpty && !others.isEmpty {
            let extra = categoryRows(others)
            extra.isHidden = true
            let more = NativeButton("其它分类（\(others.count)） ▸") {}
            more.bezelStyle = .inline
            more.onPress = { [weak extra, weak more] in
                guard let extra else { return }
                extra.isHidden.toggle()
                more?.title = "其它分类（\(others.count)） \(extra.isHidden ? "▸" : "▾")"
            }
            rows += [more, extra]
        }
        let body = NativeUI.stack(rows, spacing: 16)
        for row in rows { row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        let done = NativeButton("完成") { [weak self, weak parent] in
            if let sheet = self?.mappingWindow { parent?.endSheet(sheet) }
            self?.mappingWindow = nil
        }
        done.keyEquivalent = "\r"
        NativeUI.primary(done)
        let header = NativeUI.stack([
            NativeUI.label("选择目标相册", size: 26, weight: .semibold, color: NativeUI.ink),
            NativeUI.label("先显示本批有照片的分类。选择即保存，但不会创建相册或修改照片。", color: NativeUI.muted)
        ], spacing: 12)
        let footer = NativeUI.commandBar(message: NativeUI.label("同名相册有歧义时，请按数量和标识选择。", size: 12, color: NativeUI.muted), actions: done)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "选择目标相册"
        sheet.contentView = NativeUI.sheet(header: header, body: body, footer: footer)
        sheet.isReleasedWhenClosed = false
        mappingWindow = sheet
        parent.beginSheet(sheet)
    }

    private func moveSelection(_ index: Int) {
        guard task.state.canReview, !isBusy, index >= 4 else { return }
        let categoryIdentifier = index == 4 ? nil : categoryEntries[index - 5].1.id
        let selected = collection.selectionIndexPaths.map { task.results[visibleIndices[$0.item]] }
        for result in selected {
            if let identifier = categoryIdentifier,
               task.scheme(for: result)?.categories.contains(where: { $0.id == identifier && $0.isEnabled }) != true { continue }
            onAction(.categoryChanged(assetIdentifier: result.id, categoryIdentifier: categoryIdentifier))
        }
        collection.selectionIndexPaths = []
        bulk.selectItem(at: 0)
        updateBulkAvailability()
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        updateBulkAvailability()
    }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        updateBulkAvailability()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleIndices.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("photo"), for: indexPath) as! PhotoReviewItem
        let index = visibleIndices[indexPath.item]
        let result = task.results[index]
        item.configure(task: task, result: result, index: index, thumbnail: thumbnail, onAction: onAction,
                       isEditable: task.state.canReview && !isBusy, onInspect: { [weak self] in
            guard let self else { return }
            inspector?.close()
            inspector = PhotoInspectorWindowController(task: task, assetIdentifier: result.id, thumbnail: thumbnail, onAction: onAction)
            inspector?.showWindow(nil)
        })
        return item
    }

    override func viewWillDisappear() { inspector?.close(); super.viewWillDisappear() }
}

@MainActor
private final class PhotoReviewItem: NSCollectionViewItem {
    private let photo = NSImageView()
    private let scheme = NativeUI.label("", size: 12, weight: .medium, color: NativeUI.muted)
    private let reason = NativeUI.label("", size: 12, color: NativeUI.muted)
    private let category = NativePopUpButton()
    private var approval: NativeButton!
    private var inspect: NativeButton!
    private var imageTask: Task<Void, Never>?
    private var assetIdentifier: String?
    private var hasLoadedImage = false

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    private func updateSelectionAppearance() {
        guard isViewLoaded, let box = view as? NSBox else { return }
        box.borderWidth = isSelected ? 2 : 1
        box.borderColor = isSelected ? NativeUI.accent : NativeUI.divider
    }

    override func loadView() {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = NativeUI.surface
        box.borderColor = NativeUI.divider
        box.borderWidth = 1
        box.cornerRadius = 12
        box.contentViewMargins = NSSize(width: 12, height: 12)
        photo.imageScaling = .scaleProportionallyDown
        photo.heightAnchor.constraint(equalToConstant: 204).isActive = true
        scheme.heightAnchor.constraint(equalToConstant: 16).isActive = true
        reason.maximumNumberOfLines = 2
        reason.heightAnchor.constraint(equalToConstant: 32).isActive = true
        approval = NativeButton("加入相册", checkbox: true) {}
        inspect = NativeButton("详情") {}
        inspect.bezelStyle = .inline
        inspect.setAccessibilityLabel("放大照片与查看分类理由")
        inspect.toolTip = "放大照片与查看分类理由"
        category.heightAnchor.constraint(equalToConstant: 32).isActive = true
        for control in [approval, inspect] as [NSControl] {
            control.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let actions = NativeUI.stack([approval, inspect], horizontal: true, spacing: 12)
        let content = NativeUI.stack([photo, scheme, reason, category, actions], spacing: 8)
        NativeUI.pin(content, to: box.contentView!)
        photo.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        category.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        view = box
        updateSelectionAppearance()
    }

    func configure(task: PhotoClassificationTask, result: PhotoClassificationResult, index: Int,
                   thumbnail: @escaping (String, CGFloat) async -> NSImage?, onAction: @escaping (PhotoReviewAction) -> Void,
                   isEditable: Bool, onInspect: @escaping () -> Void) {
        _ = view
        scheme.stringValue = "\(index + 1) · \(task.scheme(for: result)?.name ?? "未知方案")"
        reason.stringValue = result.reason
        inspect.onPress = onInspect
        let categories = task.scheme(for: result)?.categories.filter(\.isEnabled) ?? []
        category.removeAllItems()
        category.addItems(withTitles: ["待分类"] + categories.map(\.name))
        let selected = categories.firstIndex { $0.id == result.effectiveCategoryIdentifier }
        category.selectItem(at: selected.map { $0 + 1 } ?? 0)
        category.isEnabled = isEditable
        category.setAccessibilityIdentifier("photo-category-\(index)")
        category.setAccessibilityLabel("照片分类")
        category.onSelection = { index in
            guard isEditable else { return }
            let identifier = index > 0 ? categories[index - 1].id : nil
            onAction(.categoryChanged(assetIdentifier: result.id, categoryIdentifier: identifier))
        }
        approval.state = result.effectiveCategoryIdentifier != nil && task.approvedAssetIdentifiers.contains(result.id) ? .on : .off
        approval.isEnabled = isEditable && result.effectiveCategoryIdentifier != nil
        approval.setAccessibilityIdentifier("approve-photo-\(index)")
        approval.onPress = { [weak self] in
            guard isEditable else { return }
            onAction(.approvalChanged(assetIdentifier: result.id, approved: self?.approval.state == .on))
        }
        if assetIdentifier != result.id || !hasLoadedImage {
            imageTask?.cancel()
            assetIdentifier = result.id
            hasLoadedImage = false
            photo.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "照片预览")
            imageTask = Task { [weak self] in
                let image = await thumbnail(result.id, 420)
                guard !Task.isCancelled, self?.assetIdentifier == result.id else { return }
                if let image {
                    self?.photo.image = image
                    self?.hasLoadedImage = true
                }
            }
        }
    }

    override func prepareForReuse() {
        imageTask?.cancel()
        super.prepareForReuse()
    }
}
