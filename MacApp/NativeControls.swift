import AppKit

extension PhotoAlbumTarget {
    var titleForDisplay: String {
        switch self {
        case .newAlbum(let name), .existingAlbum(_, let name): return name
        case .skip: return "本次跳过"
        }
    }
}

extension PhotoClassificationTaskState {
    var localizedTitle: String {
        switch self {
        case .draft: return "待开始"
        case .running: return "分类中"
        case .paused: return "已暂停"
        case .readyForReview: return "待复核"
        case .applying: return "写入中"
        case .interrupted: return "写入中断，需检查"
        case .closed: return "已检查并关闭"
        case .applied: return "已整理"
        case .undone: return "已撤销"
        case .failed: return "失败"
        }
    }
}

@MainActor
final class NativeButton: NSButton {
    var onPress: () -> Void

    init(_ title: String, checkbox: Bool = false, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        self.title = title
        setButtonType(checkbox ? .switch : .momentaryPushIn)
        if !checkbox { bezelStyle = .rounded }
        target = self
        action = #selector(pressed)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit control") }
    @objc private func pressed() { onPress() }
}

@MainActor
final class NativePopUpButton: NSPopUpButton {
    var onSelection: (Int) -> Void = { _ in }

    init() {
        super.init(frame: .zero, pullsDown: false)
        target = self
        action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit control") }
    @objc private func changed() { onSelection(indexOfSelectedItem) }
}

@MainActor
enum NativeUI {
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    static func stack(_ views: [NSView], horizontal: Bool = false, spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = horizontal ? .horizontal : .vertical
        stack.alignment = horizontal ? .centerY : .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }

    static func formRow(_ title: String, control: NSView) -> NSStackView {
        let label = label(title, color: .secondaryLabelColor)
        label.widthAnchor.constraint(equalToConstant: 125).isActive = true
        return stack([label, control], horizontal: true)
    }

    static func scroll(_ content: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return scroll
    }
}
