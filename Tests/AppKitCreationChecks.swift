import AppKit
import Foundation

@main
@MainActor
enum AppKitCreationChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        var request: (PhotoClassificationSourceScope, String, Int)?
        let controller = NewTaskViewController { action in
            if case .create(let source, _, let model, let limit) = action { request = (source, model, limit) }
        }
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 740, height: 700))
        window.makeKeyAndOrderFront(nil)
        controller.update(count: 42, limited: true, albums: [], connection: .unavailable("synthetic offline"),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "", isBusy: false)
        window.contentView?.layoutSubtreeIfNeeded()
        let views = descendants(controller.view)
        let create = views.compactMap { $0 as? NSButton }.first { $0.title == "创建下一批任务" }!
        assert(!create.isEnabled, "An unavailable local model must prevent task creation")
        let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
        assert(labels.contains("可访问照片：42 张（仅授权范围）") && labels.contains("synthetic offline"))
        let loaded = LMStudioModelDescriptor(type: "llm", key: "fixture", displayName: "Synthetic Vision",
                                            capabilities: .init(vision: true), loadedInstances: [.init(id: "loaded-fixture")])
        controller.update(count: 42, limited: true, albums: [], connection: .connected([loaded]),
                          endpoint: "http://127.0.0.1:1234/v1", preferredModel: "loaded-fixture", isBusy: false)
        let batch = views.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityIdentifier() == "batch-size" }!
        assert(batch.itemTitles == ["10 张 · 先试一批", "50 张", "100 张"])
        batch.selectItem(at: 1)
        create.performClick(nil)
        assert(request?.0 == .allPhotos && request?.1 == "loaded-fixture" && request?.2 == 50,
               "Creating a batch must preserve the chosen source, loaded instance and limit")
        window.close()
        print("AppKit creation checks passed: unavailable model, limited count and 50-photo request; no Photos/model access")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        var result = [view]
        for child in view.subviews { result += descendants(child) }
        return result
    }
}
