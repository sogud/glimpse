import AppKit
import Foundation

@main
@MainActor
enum AppKitReviewChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        let now = Date(timeIntervalSince1970: 0)
        let task = PhotoClassificationTask(
            id: UUID(), title: "合成任务", source: .allPhotos, state: .readyForReview,
            modelIdentifier: "synthetic-vision", ordinaryScheme: .ordinaryDefault,
            screenshotScheme: .screenshotDefault, assetFingerprints: [], results: [],
            targetsByCategory: [:], approvedAssetIdentifiers: [], mutations: [],
            createdAt: now, updatedAt: now
        )
        let controller = PhotoReviewViewController(task: task, albums: [], thumbnail: { _, _ in nil }, onAction: { _ in })
        let window = NSWindow(contentViewController: controller)
        window.title = "Glimpse · 合成界面检查"
        window.setContentSize(NSSize(width: 900, height: 650))
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        let views = descendants(controller.view)
        assert(views.compactMap { ($0 as? NSTextField)?.stringValue }.contains("暂无分类结果"),
               "An empty review must explain that there are no results")
        let write = views.compactMap { $0 as? NSButton }.first { $0.title == "确认写入相册" }
        assert(write?.isEnabled == false, "An empty review must not allow album writes")
        window.close()

        var reviewedTask = task
        let category = PhotoClassificationScheme.ordinaryDefault.categories[0]
        let fingerprint = PhotoClassificationFingerprint(
            assetIdentifier: "synthetic-ordinary", modificationDate: nil, modelIdentifier: "synthetic-vision",
            analyzerVersion: 2, schemeIdentifier: reviewedTask.ordinaryScheme.id, schemeVersion: 1
        )
        reviewedTask.assetFingerprints = [fingerprint]
        reviewedTask.results = [.init(fingerprint: fingerprint, categoryIdentifier: category.id, reason: "合成照片，无个人数据")]
        reviewedTask.approvedAssetIdentifiers = [fingerprint.assetIdentifier]
        let fixtureImage = NSImage(size: NSSize(width: 40, height: 30))
        var writeCalls = 0
        var review: PhotoReviewViewController!
        review = PhotoReviewViewController(task: reviewedTask, albums: [], thumbnail: { _, _ in
            try? await Task.sleep(for: .milliseconds(300))
            return Task.isCancelled ? nil : fixtureImage
        }, onAction: { action in
            if case .categoryChanged(let identifier, let selected) = action {
                reviewedTask.reviewCategory(assetIdentifier: identifier, categoryIdentifier: selected)
                review.update(task: reviewedTask, albums: [])
            }
            if case .apply = action { writeCalls += 1 }
        })
        let reviewWindow = NSWindow(contentViewController: review)
        reviewWindow.setContentSize(NSSize(width: 900, height: 650))
        reviewWindow.makeKeyAndOrderFront(nil)
        reviewWindow.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let choices = descendants(review.view).compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityIdentifier() == "photo-category-0" }
        assert(choices != nil, "Each visible photo must have a category menu")
        assert(choices!.itemTitles.contains("人物与自拍") && !choices!.itemTitles.contains("聊天社交"),
               "An ordinary photo must not offer screenshot categories")
        choices!.selectItem(withTitle: "待分类")
        NSApplication.shared.sendAction(choices!.action!, to: choices!.target, from: choices)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        assert(reviewedTask.results[0].effectiveCategoryIdentifier == nil)
        let approval = descendants(review.view).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "approve-photo-0" }
        assert(approval?.state == .off && approval?.isEnabled == false,
               "Choosing unclassified must remove and disable write approval")
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        assert(descendants(review.view).compactMap { $0 as? NSImageView }.contains { $0.image === fixtureImage },
               "Editing during thumbnail loading must not leave a permanent placeholder")
        reviewedTask.state = .applied
        review.update(task: reviewedTask, albums: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let locked = descendants(review.view).compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityIdentifier() == "photo-category-0" }
        assert(locked?.isEnabled == false, "A completed task must be read-only")
        assert(descendants(review.view).compactMap { $0 as? NSButton }.contains { $0.title == "撤销本次整理" },
               "An applied task must expose the recorded-membership undo action")

        reviewedTask.state = .readyForReview
        reviewedTask.reviewCategory(assetIdentifier: fingerprint.assetIdentifier, categoryIdentifier: category.id)
        reviewedTask.targetsByCategory[category.id] = .newAlbum(name: "合成验证相册")
        review.update(task: reviewedTask, albums: [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let confirmWrite = descendants(review.view).compactMap { $0 as? NSButton }
            .first { $0.title == "确认写入相册" }!
        assert(confirmWrite.isEnabled)
        confirmWrite.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        assert(reviewWindow.attachedSheet != nil, "Album writing must first open a confirmation sheet")
        let sheet = reviewWindow.attachedSheet!
        assert(descendants(sheet.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
            .contains { $0.contains("合成验证相册") }, "Confirmation must name the actual target album")
        let cancel = descendants(sheet.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "取消" }!
        cancel.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        assert(writeCalls == 0, "Cancelling confirmation must not emit an album write")
        let mapping = descendants(review.view).compactMap { $0 as? NSButton }.first { $0.title == "目标相册映射" }!
        mapping.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let mappingSheet = reviewWindow.attachedSheet!
        assert(descendants(mappingSheet.contentView!).compactMap { $0 as? NSPopUpButton }
            .contains { $0.titleOfSelectedItem?.contains("合成验证相册") == true },
               "Mapping must display the saved target even when it is not in the current choices")
        descendants(mappingSheet.contentView!).compactMap { $0 as? NSButton }
            .first { $0.title == "完成" }!.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        review.update(task: reviewedTask, albums: [], isBusy: true)
        assert(!confirmWrite.isEnabled, "Album writing must be disabled while another operation is active")
        reviewWindow.close()
        print("AppKit review checks passed: empty state, scheme-aware review, thumbnail refresh, read-only and cancel-before-write; no Photos/model access")
        if CommandLine.arguments.contains("--preview") { showPreview(task) }
    }

    static func showPreview(_ emptyTask: PhotoClassificationTask) {
        var task = emptyTask
        task.title = "10 张合成照片 · 复核预览"
        for index in 0..<10 {
            let scheme = index < 5 ? task.ordinaryScheme : task.screenshotScheme
            let category = scheme.categories[index % 5]
            let fingerprint = PhotoClassificationFingerprint(
                assetIdentifier: "synthetic-\(index)", modificationDate: nil, modelIdentifier: "synthetic-vision",
                analyzerVersion: 2, schemeIdentifier: scheme.id, schemeVersion: scheme.version
            )
            task.assetFingerprints.append(fingerprint)
            task.results.append(.init(fingerprint: fingerprint, categoryIdentifier: category.id,
                                      reason: "合成示例 \(index + 1)：\(category.classificationDescription)"))
            task.targetsByCategory[category.id] = .newAlbum(name: "合成预览 · \(category.name)")
            task.approvedAssetIdentifiers.insert(fingerprint.assetIdentifier)
        }
        let controller = PhotoReviewViewController(task: task, albums: [], thumbnail: { identifier, _ in
            NSImage(systemSymbolName: identifier.hasSuffix("0") ? "person.crop.square" : "photo.stack",
                    accessibilityDescription: "合成图片，不是真实照片")
        }, onAction: { _ in })
        let window = NSWindow(contentViewController: controller)
        window.title = "Glimpse · 合成数据预览"
        window.setContentSize(NSSize(width: 1000, height: 760))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.run()
        withExtendedLifetime(window) {}
    }

    static func descendants(_ view: NSView) -> [NSView] {
        var result = [view]
        for child in view.subviews { result += descendants(child) }
        return result
    }
}
