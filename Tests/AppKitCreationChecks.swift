import AppKit
import Foundation

@main
@MainActor
enum AppKitCreationChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        var request: (PhotoClassificationSourceScope, String, Int)?
        let controller = NewTaskViewController { action in
            if case .startClassification(let source, _, let model, let limit) = action { request = (source, model, limit) }
        }
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 740, height: 700))
        window.makeKeyAndOrderFront(nil)
        controller.update(count: 42, limited: true, albums: [], connection: .unavailable("synthetic offline"),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "", isBusy: false)
        window.contentView?.layoutSubtreeIfNeeded()
        let views = descendants(controller.view)
        let heading = views.compactMap { $0 as? NSTextField }.first { ($0.font?.pointSize ?? 0) >= 22 }!
        for size in [NSSize(width: 740, height: 700), NSSize(width: 930, height: 780)] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            let rect = controller.view.convert(heading.bounds, from: heading)
            let topInset = controller.view.isFlipped ? rect.minY : controller.view.bounds.maxY - rect.maxY
            assert(topInset >= 0 && topInset <= 40,
                   "A new batch must start at the top, not below a large empty area or outside the viewport: \(topInset)")
            let step = views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "1  开始分类" }!
            let scope = views.compactMap { $0 as? NSTextField }.first { $0.stringValue == "选择这一批照片" }!
            let stepRect = controller.view.convert(step.bounds, from: step)
            let scopeRect = controller.view.convert(scope.bounds, from: scope)
            let gap = stepRect.minY - scopeRect.maxY
            assert(gap >= 16 && gap <= 32, "Short form sections must not stretch into empty space: \(gap)")
        }
        let primary = views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "start-classification" }
        assert(primary?.title == "开始分类 10 张", "The primary action must say what happens next and include the batch size")
        let create = primary!
        let actionRect = controller.view.convert(create.bounds, from: create)
        assert(abs(controller.view.bounds.maxX - actionRect.maxX - 28) < 1,
               "The primary action must align with the right edge of the workspace")
        assert(actionRect.minY >= 0 && actionRect.minY <= 40, "The primary action must stay near the bottom, not float in an oversized footer")
        assert(!create.isEnabled, "An unavailable local model must prevent task creation")
        let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
        assert(labels.contains("可访问照片：42 张（仅授权范围）") && labels.contains("synthetic offline"))
        assert(views.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("synthetic offline") && !$0.isHiddenOrHasHiddenAncestor
        }, "The actual connection error must be visible without discovering advanced settings")
        let loaded = LMStudioModelDescriptor(type: "llm", key: "fixture", displayName: "Synthetic Vision",
                                            capabilities: .init(vision: true), loadedInstances: [.init(id: "loaded-fixture")])
        controller.update(count: 42, limited: true, albums: [], connection: .connected([loaded]),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "loaded-fixture", isBusy: false)
        let batch = views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityIdentifier() == "batch-size" }!
        assert(batch.itemTitles == ["10 张 · 先试一批", "50 张", "100 张"])
        batch.selectItem(at: 1)
        NSApplication.shared.sendAction(batch.action!, to: batch.target, from: batch)
        assert(create.title == "开始分类 50 张", "Changing the batch must update the next action")
        create.performClick(nil)
        assert(request?.0 == .allPhotos && request?.1 == "loaded-fixture" && request?.2 == 50,
               "Creating a batch must preserve the chosen source, loaded instance and limit")
        let unloaded = LMStudioModelDescriptor(type: "llm", key: "fixture", displayName: "Synthetic Vision",
                                              capabilities: .init(vision: true), loadedInstances: [])
        request = nil
        controller.update(count: 42, limited: true, albums: [], connection: .connected([unloaded]),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "loaded-fixture", isBusy: false)
        assert(!create.isEnabled, "A downloaded but unloaded model must not allow classification")
        assert(views.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("无需重新下载") && !$0.isHiddenOrHasHiddenAncestor
        }, "An unloaded model must show the exact next step without asking for another download")
        create.performClick(nil)
        assert(request == nil)
        controller.update(count: 42, limited: true, albums: [], connection: .checking,
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "loaded-fixture", isBusy: false)
        assert(!create.isEnabled, "Checking is not a loaded model")
        controller.update(count: 0, limited: true, albums: [], connection: .connected([loaded]),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "loaded-fixture", isBusy: false)
        assert(!create.isEnabled, "No accessible photos must prevent an empty batch")
        controller.update(count: 42, limited: true, albums: [], connection: .connected([loaded]),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "loaded-fixture", isBusy: true)
        assert(!create.isEnabled && !batch.isEnabled, "An active operation must prevent starting or changing a batch")
        create.performClick(nil)
        assert(request == nil, "Unavailable, empty and busy states must not send a start request")
        window.close()
        print("AppKit creation checks passed: offline/checking/unloaded models, empty/busy states, limited count and 50-photo request; no Photos/model access")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        var result = [view]
        for child in view.subviews { result += descendants(child) }
        return result
    }
}
