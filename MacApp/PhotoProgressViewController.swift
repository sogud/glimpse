import AppKit

enum PhotoProgressAction {
    case pause
    case startOrContinue
}

@MainActor
final class PhotoProgressViewController: NSViewController {
    private let onAction: (PhotoProgressAction) -> Void
    private let heading = NativeUI.label("", size: 26, weight: .semibold, color: NativeUI.ink)
    private let source = NativeUI.label("", color: NativeUI.muted)
    private let count = NativeUI.label("", size: 34, weight: .semibold, color: NativeUI.ink)
    private let details = NativeUI.label("", color: NativeUI.muted)
    private let nextStep = NativeUI.label("", size: 12, color: NativeUI.muted)
    private let indicator = NSProgressIndicator()
    private var action: NativeButton!

    init(onAction: @escaping (PhotoProgressAction) -> Void) {
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic AppKit view") }

    override func loadView() {
        count.font = .monospacedDigitSystemFont(ofSize: 34, weight: .semibold)
        indicator.isIndeterminate = false
        indicator.minValue = 0
        action = NativeButton("暂停分类") {}
        action.setAccessibilityIdentifier("classification-progress-action")
        NativeUI.primary(action)
        let content = NativeUI.stack([
            heading, NativeUI.steps(current: 1), source, count, indicator, details,
            NativeUI.label("图片逐张发送给本机模型。分析完成后，会自动进入检查页。", color: NativeUI.muted)
        ], spacing: 24)
        content.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)
        for child in [source, indicator, details] as [NSView] {
            child.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56).isActive = true
        }
        view = NativeUI.workspace(content: content, footer: NativeUI.commandBar(message: nextStep, actions: action))
    }

    func update(task: PhotoClassificationTask, isPausing: Bool, canStartOrContinue: Bool) {
        _ = view
        let progress = task.progress
        source.stringValue = task.title
        count.stringValue = "\(progress.analyzed) / \(progress.total) 张已分析"
        details.stringValue = "已分类 \(progress.classified) · 待分类 \(progress.needsReview) · 未分析 \(progress.remaining)"
        indicator.maxValue = Double(max(progress.total, 1))
        indicator.doubleValue = Double(progress.analyzed)
        if isPausing {
            heading.stringValue = "正在暂停分类"
            nextStep.stringValue = "等待当前请求结束。\n结束前不能继续，也不能开始新的一批。"
            action.isEnabled = false
            NativeUI.primaryTitle(action, title: "正在暂停…")
        } else if task.state == .running {
            heading.stringValue = "正在分类这批照片"
            nextStep.stringValue = "分析完成后，自动进入检查页。\n现在不会修改相册。"
            action.isEnabled = true
            NativeUI.primaryTitle(action, title: "暂停分类")
            action.onPress = { [weak self] in self?.onAction(.pause) }
        } else {
            heading.stringValue = task.state == .failed ? "这批分类还未完成" : (task.state == .draft ? "准备开始分类" : "分类已暂停")
            nextStep.stringValue = canStartOrContinue ? "继续处理同一批，保留已完成结果。\n不会增加新照片或自动改动相册。" : "请等待当前操作结束，再继续这批照片。"
            action.isEnabled = task.state.canStartOrContinueInference && canStartOrContinue
            NativeUI.primaryTitle(action, title: task.state == .draft ? "开始分类" : (task.state == .failed ? "重试这批照片" : "继续分类"))
            action.onPress = { [weak self] in self?.onAction(.startOrContinue) }
        }
    }
}
