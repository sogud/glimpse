import AppKit
import Foundation

@main
@MainActor
enum AppKitProgressChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        let scheme = PhotoClassificationScheme.ordinaryDefault
        let fingerprints = ["a", "b", "c"].map {
            PhotoClassificationFingerprint(assetIdentifier: $0, modificationDate: nil, modelIdentifier: "synthetic",
                analyzerVersion: 2, schemeIdentifier: scheme.id, schemeVersion: scheme.version)
        }
        var task = PhotoClassificationTask(id: UUID(), title: "合成进度检查 · 3 张", source: .allPhotos, state: .running,
            modelIdentifier: "synthetic", ordinaryScheme: scheme, screenshotScheme: .screenshotDefault,
            assetFingerprints: fingerprints, results: [
                .init(fingerprint: fingerprints[0], categoryIdentifier: "ordinary:people", reason: "合成"),
                .init(fingerprint: fingerprints[1], categoryIdentifier: nil, reason: "合成不确定")
            ], targetsByCategory: [:], approvedAssetIdentifiers: [], mutations: [], createdAt: Date(), updatedAt: Date())
        var pauses = 0
        var resumes = 0
        let controller = PhotoProgressViewController {
            switch $0 {
            case .pause: pauses += 1
            case .startOrContinue: resumes += 1
            }
        }
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 720, height: 658))
        window.makeKeyAndOrderFront(nil)
        controller.update(task: task, isPausing: false, canStartOrContinue: false)
        window.contentView?.layoutSubtreeIfNeeded()
        let button = descendants(controller.view).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "classification-progress-action" }!
        assert(button.title == "暂停分类" && button.isEnabled)
        button.performClick(nil)
        assert(pauses == 1 && resumes == 0)
        let labels = descendants(controller.view).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
        assert(labels.contains("2 / 3 张已分析") && labels.contains("待分类 1") && labels.contains("未分析 1"),
               "Progress must distinguish analyzed, uncertain and remaining photos")
        task.state = .paused
        controller.update(task: task, isPausing: true, canStartOrContinue: false)
        assert(button.title == "正在暂停…" && !button.isEnabled, "Waiting for cancellation must never look resumable")
        controller.update(task: task, isPausing: false, canStartOrContinue: false)
        assert(!button.isEnabled, "Another active operation must block resuming this batch")
        controller.update(task: task, isPausing: false, canStartOrContinue: true)
        assert(button.title == "继续分类" && button.isEnabled)
        button.performClick(nil)
        assert(resumes == 1 && pauses == 1)
        let rect = controller.view.convert(button.bounds, from: button)
        let alignmentRect = controller.view.convert(button.alignmentRect(forFrame: button.frame), from: button.superview)
        assert(rect.minY >= 0 && rect.minY <= 40 && abs(alignmentRect.maxX - controller.view.bounds.maxX + 28) < 1,
               "The button must remain visible and its alignment rectangle must respect the 28-point trailing margin")
        window.close()
        print("AppKit progress checks passed: counts, pause, waiting and same-batch resume; no Photos/model access")
    }

    static func descendants(_ view: NSView) -> [NSView] {
        var result = [view]
        for child in view.subviews { result += descendants(child) }
        return result
    }
}
