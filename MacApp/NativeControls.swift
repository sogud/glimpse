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
private final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class NativeSurfaceView: NSView {
    var fillColor: NSColor = NativeUI.canvas
    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        dirtyRect.fill()
    }
}

@MainActor
enum NativeUI {
    static let canvas = color(light: 0xF7F8F4, dark: 0x171D19)
    static let sidebar = color(light: 0xE9EDE6, dark: 0x202922)
    static let surface = color(light: 0xFFFFFF, dark: 0x29332C)
    static let ink = color(light: 0x252E28, dark: 0xEEF2EA)
    static let muted = color(light: 0x58665C, dark: 0xAFBDB2)
    static let accent = color(light: 0x306647, dark: 0xA5D0B2)
    static let divider = color(light: 0xD4DDD3, dark: 0x48564B)
    static let actionFill = NSColor(srgbRed: 48.0 / 255, green: 102.0 / 255, blue: 71.0 / 255, alpha: 1)

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        let lightColor = rgb(light)
        let darkColor = rgb(dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    static func primary(_ button: NSButton) {
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.bezelColor = actionFill
        button.contentTintColor = .white
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        primaryTitle(button, title: button.title)
    }

    static func primaryTitle(_ button: NSButton, title: String) {
        button.title = title
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: button.isEnabled ? NSColor.white : NSColor.disabledControlTextColor
        ])
    }

    static func steps(current: Int) -> NSStackView {
        var views: [NSView] = []
        for index in 0..<3 {
            if index > 0 { views.append(label("›", color: muted)) }
            let step = label("", size: 12)
            step.tag = index + 1
            views.append(step)
        }
        let strip = stack(views, horizontal: true, spacing: 16)
        updateSteps(strip, current: current)
        return strip
    }

    static func updateSteps(_ strip: NSStackView, current: Int) {
        let titles = ["开始分类", "检查结果", "加入相册"]
        for field in strip.views.compactMap({ $0 as? NSTextField }) where field.tag > 0 {
            let prefix = field.tag < current ? "✓" : "\(field.tag)"
            field.stringValue = "\(prefix)  \(titles[field.tag - 1])"
            field.font = .systemFont(ofSize: 12, weight: field.tag == current ? .semibold : .regular)
            field.textColor = field.tag == current ? accent : muted
        }
    }

    static func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    static func field(_ title: String, control: NSView) -> NSStackView {
        let field = stack([label(title, weight: .medium, color: ink), control], spacing: 8)
        control.widthAnchor.constraint(equalTo: field.widthAnchor).isActive = true
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return field
    }

    static func workspace(content: NSView, footer: NSView) -> NSView {
        let root = NativeSurfaceView(frame: NSRect(x: 0, y: 0, width: 850, height: 700))
        let scroll = self.scroll(content)
        let line = separator()
        for child in [scroll, line, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -16),
            line.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            line.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            line.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: line.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: line.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        return root
    }

    static func commandBar(message: NSView, actions: NSView) -> NSView {
        let bar = NSView()
        let preferredHeight = bar.heightAnchor.constraint(equalToConstant: 44)
        preferredHeight.priority = .defaultHigh
        preferredHeight.isActive = true
        for child in [message, actions] {
            child.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(child)
        }
        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            message.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -24),
            message.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            message.topAnchor.constraint(greaterThanOrEqualTo: bar.topAnchor),
            message.bottomAnchor.constraint(lessThanOrEqualTo: bar.bottomAnchor),
            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            actions.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            actions.topAnchor.constraint(greaterThanOrEqualTo: bar.topAnchor),
            actions.bottomAnchor.constraint(lessThanOrEqualTo: bar.bottomAnchor)
        ])
        return bar
    }

    static func sheet(header: NSView, body: NSView, footer: NSView) -> NSView {
        let root = NativeSurfaceView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        let scroll = self.scroll(body)
        let line = separator()
        for child in [header, scroll, line, footer] {
            child.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -16),
            line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        return root
    }

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
        if !horizontal { stack.setHuggingPriority(.required, for: .vertical) }
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
        let document = TopAlignedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let fittingHeight = document.heightAnchor.constraint(equalTo: content.heightAnchor)
        fittingHeight.priority = .init(1)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: content.heightAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.widthAnchor.constraint(equalTo: document.widthAnchor),
            fittingHeight
        ])
        return scroll
    }
}
