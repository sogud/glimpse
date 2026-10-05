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
    private let heading = NativeUI.label("", size: 22, weight: .semibold)
    private let summary = NativeUI.label("", color: .secondaryLabelColor)
    private let empty = NativeUI.label("暂无分类结果", color: .secondaryLabelColor)
    private let collection = NSCollectionView()
    private var isBusy = false
    private var writeButton: NativeButton!
    private var undoButton: NativeButton!
    private var acknowledgeButton: NativeButton!
    private var recheckButton: NativeButton!
    private var mappingWindow: NSWindow?
    private var inspector: PhotoInspectorWindowController?
    private let filter = NativePopUpButton()
    private let bulk = NativePopUpButton()
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
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 850, height: 650))
        writeButton = NativeButton("确认写入相册") { [weak self] in self?.confirmWrite() }
        undoButton = NativeButton("撤销本次整理") { [weak self] in self?.confirmUndo() }
        acknowledgeButton = NativeButton("已检查，关闭任务") { [weak self] in self?.onAction(.acknowledgeInterruption) }
        recheckButton = NativeButton("复查本批照片变更") { [weak self] in self?.onAction(.recheck) }
        let mapping = NativeButton("目标相册映射") { [weak self] in self?.showMapping() }
        let actions = NativeUI.stack([writeButton, mapping, recheckButton, undoButton, acknowledgeButton], horizontal: true)
        filter.onSelection = { [weak self] index in
            self?.selectedFilter = index
            self?.reloadPhotos()
        }
        bulk.onSelection = { [weak self] index in self?.moveSelection(index) }
        let header = NativeUI.stack([heading, summary, actions, NativeUI.stack([filter, bulk], horizontal: true), empty])
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 215, height: 330)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        collection.collectionViewLayout = layout
        collection.frame = NSRect(x: 0, y: 0, width: 800, height: 450)
        collection.autoresizingMask = [.width]
        collection.backgroundColors = [.windowBackgroundColor]
        collection.register(PhotoReviewItem.self, forItemWithIdentifier: .init("photo"))
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = collection
        root.addSubview(header)
        root.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])
        view = root
        root.layoutSubtreeIfNeeded()
        render()
    }

    func update(task: PhotoClassificationTask, albums: [PhotoAlbumDescriptor], isBusy: Bool = false) {
        self.task = task
        self.albums = albums
        self.isBusy = isBusy
        if isViewLoaded { render() }
        inspector?.update(task: task)
    }

    private func render() {
        heading.stringValue = task.title
        let progress = task.progress
        summary.stringValue = "\(task.state.localizedTitle) · 已分析 \(progress.analyzed)/\(progress.total) · 已分类 \(progress.classified) · 待分类 \(progress.needsReview) · 可写入 \(task.writeConfirmation?.additions.count ?? 0)\n已记录新增相册归属：\(task.mutations.count)；分析完成不等于写入完成。"
        if task.state == .interrupted { summary.stringValue += "\n上次 Photos 操作中断，请检查实际相册；此任务不能重新写入或撤销。" }
        writeButton.isEnabled = !isBusy && task.writeConfirmation != nil
        undoButton.isHidden = task.state != .applied
        undoButton.isEnabled = !isBusy && !task.mutations.isEmpty
        acknowledgeButton.isHidden = task.state != .interrupted
        acknowledgeButton.isEnabled = !isBusy
        recheckButton.isHidden = !task.state.canReview
        recheckButton.isEnabled = !isBusy
        let previous = selectedFilter
        filterIdentifiers = [nil, nil] + categoryEntries.map { Optional($0.1.id) }
        filter.removeAllItems()
        filter.addItems(withTitles: ["所有分类", "待分类"] + categoryEntries.map { "\($0.0.name) · \($0.1.name)" })
        selectedFilter = min(previous, filter.numberOfItems - 1)
        filter.selectItem(at: selectedFilter)
        bulk.removeAllItems()
        bulk.addItems(withTitles: ["批量改为…", "待分类"] + categoryEntries.map { "\($0.0.name) · \($0.1.name)" })
        collection.isSelectable = task.state.canReview
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
        bulk.isEnabled = false
        collection.reloadData()
    }

    private func confirmWrite() {
        guard !isBusy, let confirmation = task.writeConfirmation, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "确认写入 Apple Photos"
        let albums = confirmation.albumCounts.keys.sorted { $0.titleForDisplay < $1.titleForDisplay }
        let rows = albums.map { "\($0.titleForDisplay)：\(confirmation.albumCounts[$0]!) 张" }
        alert.informativeText = "将 \(confirmation.additions.count) 张照片加入 \(albums.count) 个相册。\n\n"
            + rows.joined(separator: "\n")
            + "\n\n只新增相册归属，不删除照片，不移除原有归属。“待删除”仍需人工检查。"
        alert.addButton(withTitle: "确认写入")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.onAction(.apply(confirmation)) }
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
        var rows: [NSView] = [NativeUI.label("目标相册映射", size: 20, weight: .semibold)]
        for (scheme, category) in categoryEntries {
            let popup = NativePopUpButton()
            let name = PhotoClassificationPlanner.albumName(schemeName: scheme.name, category: category)
            var targets = [.newAlbum(name: name)] + albums.map { PhotoAlbumTarget.existingAlbum(identifier: $0.id, name: $0.name) } + [.skip]
            var titles = ["新建：\(name)"] + albums.map { "已有：\($0.name)（\($0.assetCount) 张 · \($0.id.prefix(8))）" } + ["本次跳过"]
            let current = task.targetsByCategory[category.id] ?? .skip
            if !targets.contains(current) {
                targets.insert(current, at: 0)
                titles.insert("当前目标：\(current.titleForDisplay)", at: 0)
            }
            popup.addItems(withTitles: titles)
            popup.selectItem(at: targets.firstIndex(of: current) ?? 0)
            popup.isEnabled = task.state.canReview
            popup.onSelection = { [weak self] index in
                guard self?.task.state.canReview == true else { return }
                self?.onAction(.targetChanged(categoryIdentifier: category.id, target: targets[index]))
            }
            rows.append(NativeUI.formRow("\(scheme.name) · \(category.name)", control: popup))
        }
        rows.append(NativeUI.label("同名歧义默认跳过，请按相册数量和标识明确选择目标。", size: 12, color: .secondaryLabelColor))
        let done = NativeButton("完成") { [weak self] in
            if let sheet = self?.mappingWindow { parent.endSheet(sheet) }
            self?.mappingWindow = nil
        }
        rows.append(done)
        let content = NativeUI.stack(rows, spacing: 14)
        content.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 580),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "相册映射"
        sheet.contentView = NativeUI.scroll(content)
        sheet.isReleasedWhenClosed = false
        mappingWindow = sheet
        parent.beginSheet(sheet)
    }

    private func moveSelection(_ index: Int) {
        guard task.state.canReview, index > 0 else { return }
        let categoryIdentifier = index == 1 ? nil : categoryEntries[index - 2].1.id
        let selected = collection.selectionIndexPaths.map { task.results[visibleIndices[$0.item]] }
        for result in selected {
            if let identifier = categoryIdentifier,
               task.scheme(for: result)?.categories.contains(where: { $0.id == identifier && $0.isEnabled }) != true { continue }
            onAction(.categoryChanged(assetIdentifier: result.id, categoryIdentifier: categoryIdentifier))
        }
        collection.selectionIndexPaths = []
        bulk.selectItem(at: 0)
        bulk.isEnabled = false
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        bulk.isEnabled = task.state.canReview && !collection.selectionIndexPaths.isEmpty
    }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        bulk.isEnabled = task.state.canReview && !collection.selectionIndexPaths.isEmpty
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleIndices.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("photo"), for: indexPath) as! PhotoReviewItem
        let index = visibleIndices[indexPath.item]
        let result = task.results[index]
        item.configure(task: task, result: result, index: index, thumbnail: thumbnail, onAction: onAction,
                       onInspect: { [weak self] in
            guard let self else { return }
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
    private let scheme = NativeUI.label("", size: 12, weight: .medium, color: .controlAccentColor)
    private let reason = NativeUI.label("", size: 12, color: .secondaryLabelColor)
    private let category = NativePopUpButton()
    private var approval: NativeButton!
    private var inspect: NativeButton!
    private var imageTask: Task<Void, Never>?
    private var assetIdentifier: String?
    private var hasLoadedImage = false

    override func loadView() {
        let box = NSBox()
        box.boxType = .custom
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 10
        box.contentViewMargins = NSSize(width: 10, height: 10)
        photo.imageScaling = .scaleProportionallyUpOrDown
        photo.heightAnchor.constraint(equalToConstant: 150).isActive = true
        reason.maximumNumberOfLines = 2
        approval = NativeButton("写入相册", checkbox: true) {}
        inspect = NativeButton("查看详情") {}
        let content = NativeUI.stack([photo, scheme, reason, category, approval, inspect], spacing: 8)
        NativeUI.pin(content, to: box.contentView!)
        photo.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        category.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        view = box
    }

    func configure(task: PhotoClassificationTask, result: PhotoClassificationResult, index: Int,
                   thumbnail: @escaping (String, CGFloat) async -> NSImage?, onAction: @escaping (PhotoReviewAction) -> Void,
                   onInspect: @escaping () -> Void) {
        _ = view
        scheme.stringValue = task.scheme(for: result)?.name ?? "未知方案"
        reason.stringValue = result.reason
        inspect.onPress = onInspect
        let categories = task.scheme(for: result)?.categories.filter(\.isEnabled) ?? []
        category.removeAllItems()
        category.addItems(withTitles: ["待分类"] + categories.map(\.name))
        let selected = categories.firstIndex { $0.id == result.effectiveCategoryIdentifier }
        category.selectItem(at: selected.map { $0 + 1 } ?? 0)
        category.isEnabled = task.state.canReview
        category.setAccessibilityIdentifier("photo-category-\(index)")
        category.setAccessibilityLabel("照片分类")
        category.onSelection = { index in
            guard task.state.canReview else { return }
            let identifier = index > 0 ? categories[index - 1].id : nil
            onAction(.categoryChanged(assetIdentifier: result.id, categoryIdentifier: identifier))
        }
        approval.state = result.effectiveCategoryIdentifier != nil && task.approvedAssetIdentifiers.contains(result.id) ? .on : .off
        approval.isEnabled = task.state.canReview && result.effectiveCategoryIdentifier != nil
        approval.setAccessibilityIdentifier("approve-photo-\(index)")
        approval.onPress = { [weak self] in
            guard task.state.canReview else { return }
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
