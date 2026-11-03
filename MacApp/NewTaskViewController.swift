import AppKit

enum NewTaskAction {
    case startClassification(source: PhotoClassificationSourceScope, title: String, modelIdentifier: String, limit: Int)
    case endpointChanged(String)
    case refresh
    case editScheme(PhotoClassificationSchemeKind)
}

@MainActor
final class NewTaskViewController: NSViewController {
    private let onAction: (NewTaskAction) -> Void
    private let countLabel = NativeUI.label("", color: NativeUI.muted)
    private let source = NativePopUpButton()
    private let batch = NativePopUpButton()
    private let album = NativePopUpButton()
    private let start = NSDatePicker()
    private let end = NSDatePicker()
    private let endpoint = NSTextField(string: "http://127.0.0.1:1234/v1")
    private let model = NativePopUpButton()
    private let status = NativeUI.label("", weight: .semibold, color: NativeUI.accent)
    private let guidance = NativeUI.label("", color: NativeUI.muted)
    private let modelDetails = NativeUI.label("", size: 12, color: NativeUI.muted)
    private let nextStep = NativeUI.label("", size: 12, color: NativeUI.muted)
    private var albumRow: NSView!
    private var dateRow: NSView!
    private var settings: NSView!
    private var startButton: NativeButton!
    private var applyEndpoint: NativeButton!
    private var refresh: NativeButton!
    private var editOrdinary: NativeButton!
    private var editScreenshot: NativeButton!
    private var settingsDisclosure: NativeButton!
    private var albums: [PhotoAlbumDescriptor] = []
    private var loadedModels: [String] = []
    private var isBusy = false
    private var accessibleCount = 0

    init(onAction: @escaping (NewTaskAction) -> Void) {
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit view") }

    override func loadView() {
        source.addItems(withTitles: ["全图库", "最近 7 天", "最近 30 天", "最近 90 天", "指定相册", "日期范围"])
        source.setAccessibilityLabel("照片范围")
        source.onSelection = { [weak self] _ in self?.refreshAvailability() }
        batch.addItems(withTitles: ["10 张 · 先试一批", "50 张", "100 张"])
        batch.setAccessibilityIdentifier("batch-size")
        batch.setAccessibilityLabel("本批数量")
        batch.onSelection = { [weak self] _ in self?.refreshAvailability() }
        album.onSelection = { [weak self] _ in self?.refreshAvailability() }
        for picker in [start, end] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
            picker.dateValue = Date()
            picker.target = self
            picker.action = #selector(dateChanged)
        }
        start.dateValue = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        albumRow = NativeUI.field("选择相册", control: album)
        dateRow = NativeUI.stack([NativeUI.formRow("开始日期", control: start),
                                 NativeUI.formRow("结束日期", control: end)], spacing: 8)
        applyEndpoint = NativeButton("应用地址") { [weak self] in
            guard let self else { return }
            onAction(.endpointChanged(endpoint.stringValue))
        }
        refresh = NativeButton("刷新模型状态") { [weak self] in self?.onAction(.refresh) }
        editOrdinary = NativeButton("普通照片分类") { [weak self] in self?.onAction(.editScheme(.ordinary)) }
        editScreenshot = NativeButton("截图分类") { [weak self] in self?.onAction(.editScheme(.screenshot)) }
        startButton = NativeButton("开始分类 10 张") { [weak self] in self?.beginClassification() }
        startButton.setAccessibilityIdentifier("start-classification")
        startButton.keyEquivalent = "\r"
        NativeUI.primary(startButton)
        model.setAccessibilityLabel("已加载的识图模型")
        model.onSelection = { [weak self] _ in self?.refreshAvailability() }
        let scopeFields = NativeUI.stack([NativeUI.field("照片范围", control: source),
                                         NativeUI.field("本批数量", control: batch)], horizontal: true, spacing: 16)
        scopeFields.distribution = .fillEqually
        let modelField = NativeUI.field("识图模型", control: model)
        let address = NativeUI.stack([endpoint, applyEndpoint], horizontal: true)
        endpoint.setAccessibilityLabel("LM Studio 本机服务地址")
        endpoint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let addressField = NativeUI.stack([NativeUI.label("本机服务地址", size: 12, color: NativeUI.muted), address], spacing: 8)
        settings = NativeUI.stack([
            modelField, addressField, modelDetails,
            NativeUI.stack([editOrdinary, editScreenshot], horizontal: true),
            NativeUI.label("App 与 CLI 的进度独立。只连接本机；不自动下载或加载模型。", size: 12, color: NativeUI.muted)
        ], spacing: 12)
        settings.isHidden = true
        settingsDisclosure = NativeButton("连接与分类设置 ▸") { [weak self] in self?.toggleSettings() }
        settingsDisclosure.bezelStyle = .inline
        settingsDisclosure.setAccessibilityLabel("展开或收起连接与分类设置")
        let heading = NativeUI.label("整理你的相册", size: 26, weight: .semibold, color: NativeUI.ink)
        heading.setAccessibilityIdentifier("workspace-heading")
        let introduction = NativeUI.stack([
            heading,
            NativeUI.steps(current: 1)
        ], spacing: 12)
        let scopeSection = NativeUI.stack([
            NativeUI.label("选择这一批照片", size: 16, weight: .semibold, color: NativeUI.ink), countLabel,
            scopeFields, albumRow, dateRow,
            NativeUI.label("会跳过已有分析结果；未完成任务保留原批次，不会重复选取。", size: 12, color: NativeUI.muted)
        ], spacing: 12)
        refresh.bezelStyle = .inline
        let readiness = NativeUI.stack([status, refresh], horizontal: true, spacing: 16)
        let modelSection = NativeUI.stack([readiness, guidance], spacing: 8)
        let line = NativeUI.separator()
        let content = NativeUI.stack([introduction, scopeSection, line, modelSection, settingsDisclosure, settings], spacing: 24)
        content.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 20, right: 28)
        for child in [introduction, scopeSection, scopeFields, albumRow, dateRow, line, modelSection, modelField, settings, addressField, address, modelDetails, guidance] as [NSView] {
            child.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56).isActive = true
        }
        let footer = NativeUI.commandBar(message: nextStep, actions: startButton)
        view = NativeUI.workspace(content: content, footer: footer)
        refreshAvailability()
    }

    func update(count: Int, limited: Bool, albums: [PhotoAlbumDescriptor], connection: LMStudioConnectionState,
                endpoint: String, preferredModel: String, isBusy: Bool) {
        _ = view
        accessibleCount = count
        countLabel.stringValue = "可访问照片：\(count) 张\(limited ? "（仅授权范围）" : "")"
        self.isBusy = isBusy
        if self.endpoint.currentEditor() == nil { self.endpoint.stringValue = endpoint }
        if self.albums != albums {
            let selected = self.albums.indices.contains(album.indexOfSelectedItem) ? self.albums[album.indexOfSelectedItem].id : nil
            self.albums = albums
            album.removeAllItems()
            album.addItems(withTitles: albums.map { "\($0.name)（\($0.assetCount) 张 · \($0.id.prefix(8))）" })
            if let index = albums.firstIndex(where: { $0.id == selected }) { album.selectItem(at: index) }
        }
        let previous = selectedModelIdentifier
        loadedModels = connection.loadedModelIdentifiers
        model.removeAllItems()
        if case .connected(let models) = connection {
            for descriptor in models {
                for instance in descriptor.loadedInstances {
                    let title = descriptor.loadedInstances.count == 1 ? descriptor.displayName : "\(descriptor.displayName) · \(instance.id)"
                    model.addItem(withTitle: title)
                }
            }
        }
        if loadedModels.isEmpty { model.addItem(withTitle: "尚未加载视觉模型") }
        else if let previous, let index = loadedModels.firstIndex(of: previous) { model.selectItem(at: index) }
        else if let index = loadedModels.firstIndex(of: preferredModel) { model.selectItem(at: index) }
        switch connection {
        case .checking:
            status.stringValue = "正在检查本机模型…"
            guidance.stringValue = "正在读取 LM Studio 的模型加载状态。"
            modelDetails.stringValue = "等待本机服务响应。"
        case .unavailable(let message):
            status.stringValue = "还没有连接到本机模型"
            guidance.stringValue = message + "\n在 LM Studio 检查本地服务和模型加载状态，然后刷新。"
            modelDetails.stringValue = message
        case .connected(let models):
            status.stringValue = loadedModels.isEmpty ? "本地服务已连接，还需加载模型" : "本机视觉模型已加载"
            guidance.stringValue = loadedModels.isEmpty ? "在 LM Studio 加载已下载的视觉模型，然后刷新。无需重新下载。" : "当前使用 \(model.titleOfSelectedItem ?? "本机视觉模型")，可在连接设置中更换。"
            modelDetails.stringValue = models.isEmpty ? "服务未返回支持图片的模型，请检查模型与 runtime。" : models.map {
                "\($0.displayName)：\($0.loadedInstances.isEmpty ? "已下载，未加载" : $0.loadedInstances.map(\.id).joined(separator: "、"))"
            }.joined(separator: "\n")
        }
        refreshAvailability()
    }

    private var selectedModelIdentifier: String? {
        let index = model.indexOfSelectedItem
        return loadedModels.indices.contains(index) ? loadedModels[index] : nil
    }

    private func refreshAvailability() {
        albumRow.isHidden = source.indexOfSelectedItem != 4
        dateRow.isHidden = source.indexOfSelectedItem != 5
        for control in [source, batch, album, start, end, endpoint, applyEndpoint, refresh, editOrdinary, editScreenshot] as [NSControl] {
            control.isEnabled = !isBusy
        }
        model.isEnabled = !isBusy && !loadedModels.isEmpty
        if selectedModelIdentifier != nil {
            guidance.stringValue = "当前使用 \(model.titleOfSelectedItem ?? "本机视觉模型")，可在连接设置中更换。"
        }
        startButton.isEnabled = !isBusy && accessibleCount > 0 && sourceScope != nil && selectedModelIdentifier != nil
        NativeUI.primaryTitle(startButton, title: "开始分类 \([10, 50, 100][batch.indexOfSelectedItem]) 张")
        if isBusy { nextStep.stringValue = "正在处理，请稍候。\n完成当前操作后才能开始下一批。" }
        else if accessibleCount == 0 { nextStep.stringValue = "当前授权范围没有照片。\n请检查照片权限，或刷新图库。" }
        else if sourceScope == nil {
            nextStep.stringValue = source.indexOfSelectedItem == 5 ? "开始日期不能晚于结束日期。" : "没有可选择的相册，请更换范围或刷新。"
        } else if loadedModels.isEmpty { nextStep.stringValue = "先连接并加载本机视觉模型。\n就绪后即可开始分类。" }
        else { nextStep.stringValue = "这里只生成分类建议。\n检查结果后，再确认加入相册。" }
    }

    private var sourceScope: PhotoClassificationSourceScope? {
        switch source.indexOfSelectedItem {
        case 0: return .allPhotos
        case 1: return .recentDays(7)
        case 2: return .recentDays(30)
        case 3: return .recentDays(90)
        case 4:
            guard albums.indices.contains(album.indexOfSelectedItem) else { return nil }
            let selected = albums[album.indexOfSelectedItem]
            return .album(identifier: selected.id, name: selected.name)
        case 5:
            guard start.dateValue <= end.dateValue else { return nil }
            return .dateRange(start: start.dateValue, end: end.dateValue)
        default: return nil
        }
    }

    private func toggleSettings() {
        settings.isHidden.toggle()
        settingsDisclosure.title = settings.isHidden ? "连接与分类设置 ▸" : "连接与分类设置 ▾"
    }

    @objc private func dateChanged() { refreshAvailability() }

    private func beginClassification() {
        guard startButton.isEnabled, let scope = sourceScope, let identifier = selectedModelIdentifier else { return }
        let limit = [10, 50, 100][batch.indexOfSelectedItem]
        onAction(.startClassification(source: scope, title: source.titleOfSelectedItem ?? "分类", modelIdentifier: identifier, limit: limit))
    }
}
