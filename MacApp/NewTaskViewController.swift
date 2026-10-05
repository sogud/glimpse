import AppKit

enum NewTaskAction {
    case create(source: PhotoClassificationSourceScope, title: String, modelIdentifier: String, limit: Int)
    case endpointChanged(String)
    case refresh
    case editScheme(PhotoClassificationSchemeKind)
}

@MainActor
final class NewTaskViewController: NSViewController {
    private let onAction: (NewTaskAction) -> Void
    private let countLabel = NativeUI.label("", color: .secondaryLabelColor)
    private let source = NativePopUpButton()
    private let batch = NativePopUpButton()
    private let album = NativePopUpButton()
    private let start = NSDatePicker()
    private let end = NSDatePicker()
    private let endpoint = NSTextField(string: "http://127.0.0.1:1234/v1")
    private let model = NativePopUpButton()
    private let status = NativeUI.label("")
    private let modelDetails = NativeUI.label("", size: 12, color: .secondaryLabelColor)
    private var albumRow: NSView!
    private var dateRow: NSView!
    private var createButton: NativeButton!
    private var applyEndpoint: NativeButton!
    private var refresh: NativeButton!
    private var editOrdinary: NativeButton!
    private var editScreenshot: NativeButton!
    private var albums: [PhotoAlbumDescriptor] = []
    private var loadedModels: [String] = []
    private var isBusy = false

    init(onAction: @escaping (NewTaskAction) -> Void) {
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit view") }

    override func loadView() {
        source.addItems(withTitles: ["全图库下一批", "最近 7 天", "最近 30 天", "最近 90 天", "指定相册", "日期范围"])
        source.onSelection = { [weak self] _ in self?.refreshAvailability() }
        batch.addItems(withTitles: ["10 张 · 先试一批", "50 张", "100 张"])
        batch.setAccessibilityIdentifier("batch-size")
        album.onSelection = { [weak self] _ in self?.refreshAvailability() }
        for picker in [start, end] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .yearMonthDay
            picker.dateValue = Date()
            picker.target = self
            picker.action = #selector(dateChanged)
        }
        start.dateValue = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        albumRow = NativeUI.formRow("相册", control: album)
        dateRow = NativeUI.stack([NativeUI.formRow("开始日期", control: start), NativeUI.formRow("结束日期", control: end)])
        applyEndpoint = NativeButton("应用地址") { [weak self] in
            guard let self else { return }
            onAction(.endpointChanged(endpoint.stringValue))
        }
        refresh = NativeButton("刷新") { [weak self] in self?.onAction(.refresh) }
        editOrdinary = NativeButton("编辑普通照片分类") { [weak self] in self?.onAction(.editScheme(.ordinary)) }
        editScreenshot = NativeButton("编辑截图分类") { [weak self] in self?.onAction(.editScheme(.screenshot)) }
        createButton = NativeButton("创建下一批任务") { [weak self] in self?.create() }
        createButton.keyEquivalent = "\r"
        model.onSelection = { [weak self] _ in self?.refreshAvailability() }
        let address = NativeUI.stack([endpoint, applyEndpoint, refresh], horizontal: true)
        endpoint.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        let content = NativeUI.stack([
            NativeUI.label("整理下一批照片", size: 24, weight: .semibold),
            NativeUI.label("本机识图 · 复核并确认后才写相册", color: .controlAccentColor), countLabel,
            NativeUI.label("原生 App 的记录与 CLI 独立。下一批会跳过已有结果及未完成任务。", size: 12, color: .secondaryLabelColor),
            NativeUI.label("照片范围", size: 16, weight: .semibold),
            NativeUI.formRow("来源", control: source), NativeUI.formRow("本批数量", control: batch), albumRow, dateRow,
            NativeUI.label("固定批次，图片逐张串行分析；不会自动写入或因继续而增加新照片。", size: 12, color: .secondaryLabelColor),
            NativeUI.label("LM Studio 本地模型", size: 16, weight: .semibold), address, status,
            NativeUI.formRow("已加载视觉实例", control: model), modelDetails,
            NativeUI.label("只连接本机回环地址；不自动下载、加载或换模型重试。需要 LM Studio 0.4+。", size: 12, color: .secondaryLabelColor),
            NativeUI.stack([editOrdinary, editScreenshot], horizontal: true), createButton
        ], spacing: 16)
        content.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        address.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48).isActive = true
        modelDetails.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48).isActive = true
        view = NativeUI.scroll(content)
        view.frame = NSRect(x: 0, y: 0, width: 740, height: 700)
        refreshAvailability()
    }

    func update(count: Int, limited: Bool, albums: [PhotoAlbumDescriptor], connection: LMStudioConnectionState,
                endpoint: String, preferredModel: String, isBusy: Bool) {
        _ = view
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
        let identifiers = connection.loadedModelIdentifiers
        if loadedModels != identifiers {
            let previous = model.titleOfSelectedItem
            loadedModels = identifiers
            model.removeAllItems()
            model.addItems(withTitles: identifiers)
            if let previous, identifiers.contains(previous) { model.selectItem(withTitle: previous) }
            else if identifiers.contains(preferredModel) { model.selectItem(withTitle: preferredModel) }
        }
        switch connection {
        case .checking:
            status.stringValue = "正在检查本地服务…"
            modelDetails.stringValue = "等待模型列表。"
        case .unavailable(let message):
            status.stringValue = "本地服务未连接"
            modelDetails.stringValue = message + "\n请在 LM Studio 启动服务，加载视觉模型后刷新。无需重新下载。"
        case .connected(let models):
            status.stringValue = "本地服务已连接"
            if models.isEmpty {
                modelDetails.stringValue = "服务没有返回支持图片输入的模型，请检查模型与 runtime。"
            } else {
                modelDetails.stringValue = models.map { "\($0.displayName) · \($0.loadedInstances.isEmpty ? "已下载，未加载" : "已加载")" }.joined(separator: "\n")
                if identifiers.isEmpty { modelDetails.stringValue += "\n请在 LM Studio 加载模型后刷新。" }
            }
        }
        refreshAvailability()
    }

    private func refreshAvailability() {
        albumRow.isHidden = source.indexOfSelectedItem != 4
        dateRow.isHidden = source.indexOfSelectedItem != 5
        for control in [source, batch, album, start, end, endpoint, model, applyEndpoint, refresh, editOrdinary, editScreenshot] as [NSControl] {
            control.isEnabled = !isBusy
        }
        createButton.isEnabled = !isBusy && sourceScope != nil && loadedModels.contains(model.titleOfSelectedItem ?? "")
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

    @objc private func dateChanged() { refreshAvailability() }

    private func create() {
        guard createButton.isEnabled, let scope = sourceScope, let identifier = model.titleOfSelectedItem else { return }
        let limit = [10, 50, 100][batch.indexOfSelectedItem]
        onAction(.create(source: scope, title: source.titleOfSelectedItem ?? "分类任务", modelIdentifier: identifier, limit: limit))
    }
}
