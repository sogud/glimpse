import AppKit

@MainActor
final class PhotoInspectorWindowController: NSWindowController, NSWindowDelegate {
    private let assetIdentifier: String
    private let onAction: (PhotoReviewAction) -> Void
    private let photo = NSImageView()
    private let reason = NativeUI.label("", color: .secondaryLabelColor)
    private let category = NativePopUpButton()
    private var imageTask: Task<Void, Never>?

    init(task: PhotoClassificationTask, assetIdentifier: String, thumbnail: @escaping (String, CGFloat) async -> NSImage?,
         onAction: @escaping (PhotoReviewAction) -> Void) {
        self.assetIdentifier = assetIdentifier
        self.onAction = onAction
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 650),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "分类详情"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        photo.imageScaling = .scaleProportionallyUpOrDown
        let content = NativeUI.stack([photo, reason, category])
        let root = NSView()
        NativeUI.pin(content, to: root, inset: 24)
        photo.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        photo.heightAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        reason.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        window.contentView = root
        update(task: task)
        imageTask = Task { [weak self] in
            let image = await thumbnail(assetIdentifier, 1200)
            if !Task.isCancelled { self?.photo.image = image }
        }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit window") }

    func update(task: PhotoClassificationTask) {
        guard let result = task.results.first(where: { $0.id == assetIdentifier }) else {
            reason.stringValue = "这张照片已不在本批记录中。"
            category.isEnabled = false
            return
        }
        let categories = task.scheme(for: result)?.categories.filter(\.isEnabled) ?? []
        let modelCategory = task.scheme(for: result)?.categories.first(where: { $0.id == result.categoryIdentifier })?.name ?? "待分类"
        reason.stringValue = "模型建议：\(modelCategory)\n\(result.reason)"
        category.removeAllItems()
        category.addItems(withTitles: ["待分类"] + categories.map(\.name))
        category.selectItem(at: categories.firstIndex(where: { $0.id == result.effectiveCategoryIdentifier }).map { $0 + 1 } ?? 0)
        category.isEnabled = task.state.canReview
        category.onSelection = { [weak self] index in
            guard task.state.canReview else { return }
            self?.onAction(.categoryChanged(assetIdentifier: result.id, categoryIdentifier: index == 0 ? nil : categories[index - 1].id))
        }
    }

    func windowWillClose(_ notification: Notification) { imageTask?.cancel() }
}
