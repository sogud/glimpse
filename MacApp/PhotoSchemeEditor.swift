import AppKit
import Combine

@MainActor
final class PhotoSchemeEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: PhotoClassificationCoordinator
    private let kind: PhotoClassificationSchemeKind
    private let table = NSTableView()
    private var subscription: AnyCancellable?

    private var scheme: PhotoClassificationScheme {
        kind == .ordinary ? coordinator.savedOrdinaryScheme : coordinator.savedScreenshotScheme
    }

    init(coordinator: PhotoClassificationCoordinator, kind: PhotoClassificationSchemeKind) {
        self.coordinator = coordinator
        self.kind = kind
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 540),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = kind == .ordinary ? "普通照片分类" : "截图分类"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        for (identifier, title, width) in [("enabled", "启用", 55.0), ("name", "分类名称", 150.0), ("description", "识图说明", 540.0)] {
            let column = NSTableColumn(identifier: .init(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.rowHeight = 40
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        let add = NativeButton("新增分类") { [weak self] in
            guard let self, coordinator.canChangeEnvironment else { return }
            coordinator.addSavedCategory(schemeKind: kind)
        }
        let remove = NativeButton("删除选中分类") { [weak self] in self?.deleteCategory() }
        let content = NativeUI.stack([
            NativeUI.label("编辑名称、说明与启用状态，只影响新任务。已有任务保留方案快照。", size: 12, color: .secondaryLabelColor),
            scroll, NativeUI.stack([add, remove], horizontal: true)
        ])
        scroll.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        let root = NSView()
        NativeUI.pin(content, to: root, inset: 20)
        window.contentView = root
        subscription = coordinator.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.table.reloadData() }
        }
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit window") }
    func numberOfRows(in tableView: NSTableView) -> Int { scheme.categories.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let category = scheme.categories[row]
        let identifier = tableColumn?.identifier.rawValue ?? ""
        if identifier == "enabled" {
            let button = NativeButton("", checkbox: true) { [weak self] in
                guard let self, coordinator.canChangeEnvironment,
                      var current = scheme.categories.first(where: { $0.id == category.id }) else { return }
                current.isEnabled.toggle()
                coordinator.updateSavedCategory(schemeKind: kind, category: current)
            }
            button.state = category.isEnabled ? .on : .off
            button.isEnabled = coordinator.canChangeEnvironment
            return button
        }
        let field = NativeEditableTextField(identifier == "name" ? category.name : category.classificationDescription) { [weak self] text in
            guard let self, coordinator.canChangeEnvironment,
                  var current = scheme.categories.first(where: { $0.id == category.id }) else { return }
            if identifier == "name" { current.name = text }
            else { current.classificationDescription = text }
            coordinator.updateSavedCategory(schemeKind: kind, category: current)
        }
        field.isEnabled = coordinator.canChangeEnvironment
        return field
    }

    private func deleteCategory() {
        guard coordinator.canChangeEnvironment, scheme.categories.indices.contains(table.selectedRow), let window else { return }
        let category = scheme.categories[table.selectedRow]
        let alert = NSAlert()
        alert.messageText = "删除分类“\(category.name)”？"
        alert.informativeText = "只影响之后创建的任务，不修改照片或旧任务。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "删除")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn, coordinator.canChangeEnvironment else { return }
            coordinator.removeSavedCategory(schemeKind: kind, categoryIdentifier: category.id)
        }
    }
}

@MainActor
private final class NativeEditableTextField: NSTextField, NSTextFieldDelegate {
    private let onCommit: (String) -> Void

    init(_ text: String, onCommit: @escaping (String) -> Void) {
        self.onCommit = onCommit
        super.init(frame: .zero)
        stringValue = text
        isEditable = true
        isSelectable = true
        isBezeled = true
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit field") }
    func controlTextDidEndEditing(_ notification: Notification) { onCommit(stringValue) }
}
