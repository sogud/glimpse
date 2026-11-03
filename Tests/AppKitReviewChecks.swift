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
        assert(views.compactMap { ($0 as? NSTextField)?.stringValue }.contains {
            $0.contains("没有分类结果") && $0.contains("重新检查") && $0.contains("开始新的一批")
        }, "An empty review must offer rechecking or a new batch, not ask users to approve nonexistent photos")
        let write = views.compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "preview-albums" }
        assert(write?.title == "预览加入相册…", "Review must explain the safe next step, not look like immediate writing")
        assert(write?.isEnabled == false, "An empty review must not allow album writes")
        for size in [NSSize(width: 720, height: 658), NSSize(width: 930, height: 758)] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            let rect = controller.view.convert(write!.bounds, from: write!)
            assert(rect.minX >= 0 && rect.maxX <= controller.view.bounds.width && rect.minY >= 0 && rect.minY <= 40,
                   "The next action must remain visible near the bottom at both supported window sizes")
        }
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
        assert(descendants(review.view).compactMap { ($0 as? NSTextField)?.stringValue }.contains("✓  检查结果"),
               "Completing album organization must advance the visible workflow, not leave review as the current step")
        assert(descendants(review.view).compactMap { ($0 as? NSTextField)?.stringValue }.contains {
            $0.contains("继续整理") && $0.contains("开始新的一批")
        }, "A completed task must explain how to start the next batch, not present undo as the continuation")
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
            .first { $0.accessibilityIdentifier() == "preview-albums" }!
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
        let mapping = descendants(review.view).compactMap { $0 as? NSButton }.first { $0.title == "选择目标相册" }!
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
        confirmationKeepsActionsVisible(task)
        approvalRespectsTheCurrentFilter(task)
        selectionHasVisibleFeedback(task)
        print("AppKit review checks passed: empty state, scheme-aware review, thumbnail refresh, read-only and cancel-before-write; no Photos/model access")
        if CommandLine.arguments.contains("--preview") { showPreview(task) }
    }

    static func selectionHasVisibleFeedback(_ emptyTask: PhotoClassificationTask) {
        var task = emptyTask
        for scheme in [task.ordinaryScheme, task.screenshotScheme] {
            let fingerprint = PhotoClassificationFingerprint(assetIdentifier: scheme.name, modificationDate: nil,
                modelIdentifier: task.modelIdentifier, analyzerVersion: 2,
                schemeIdentifier: scheme.id, schemeVersion: scheme.version)
            task.assetFingerprints.append(fingerprint)
            task.results.append(.init(fingerprint: fingerprint, categoryIdentifier: scheme.categories[0].id, reason: "合成照片"))
        }
        let controller = PhotoReviewViewController(task: task, albums: [], thumbnail: { _, _ in nil }, onAction: { _ in })
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 930, height: 658))
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let collection = descendants(controller.view).compactMap { $0 as? NSCollectionView }.first!
        let selected = Set([IndexPath(item: 0, section: 0)])
        collection.selectionIndexPaths = selected
        controller.collectionView(collection, didSelectItemsAt: selected)
        let first = collection.item(at: IndexPath(item: 0, section: 0))!
        let tile = first.view as! NSBox
        assert(tile.borderWidth == 2 && tile.borderColor.isEqual(NativeUI.accent),
               "A selected photo must have a visible accent outline for batch editing")
        let bulk = descendants(controller.view).compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "批量勾选与改类" }!
        assert(bulk.titleOfSelectedItem?.contains("1 张已选") == true,
               "The batch menu must show how many photos are selected for editing")
        let ordinary = bulk.item(withTitle: "所选照片 → \(task.ordinaryScheme.name) · \(task.ordinaryScheme.categories[0].name)")!
        let screenshot = bulk.item(withTitle: "所选照片 → \(task.screenshotScheme.name) · \(task.screenshotScheme.categories[0].name)")!
        assert(ordinary.isEnabled && !screenshot.isEnabled,
               "Selecting an ordinary photo must not enable incompatible screenshot categories")
        let mixed = Set([IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 0)])
        collection.selectionIndexPaths = mixed
        controller.collectionView(collection, didSelectItemsAt: mixed)
        assert(bulk.item(at: 4)?.isEnabled == true,
               "Mixed schemes may still be explicitly changed to unclassified")
        for index in 5..<bulk.numberOfItems {
            assert(bulk.item(at: index)?.isEnabled == false,
                   "Mixed schemes must not offer a category that would silently skip some selected photos")
        }
        first.isSelected = false
        assert(tile.borderWidth == 1 && tile.borderColor.isEqual(NativeUI.divider),
               "Deselecting a photo must restore its normal appearance")
        window.close()
    }

    static func approvalRespectsTheCurrentFilter(_ emptyTask: PhotoClassificationTask) {
        var task = emptyTask
        var approvals: [(String, Bool)] = []
        for (identifier, category) in [("a", "ordinary:people"), ("b", "ordinary:people"), ("c", "ordinary:food")] {
            let fingerprint = PhotoClassificationFingerprint(assetIdentifier: identifier, modificationDate: nil,
                modelIdentifier: task.modelIdentifier, analyzerVersion: 2,
                schemeIdentifier: task.ordinaryScheme.id, schemeVersion: task.ordinaryScheme.version)
            task.assetFingerprints.append(fingerprint)
            task.results.append(.init(fingerprint: fingerprint, categoryIdentifier: .init(rawValue: category), reason: "合成照片"))
        }
        let controller = PhotoReviewViewController(task: task, albums: [], thumbnail: { _, _ in nil }, onAction: {
            if case .approvalChanged(let identifier, let approved) = $0 { approvals.append((identifier, approved)) }
        })
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 930, height: 658))
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        let menus = descendants(controller.view).compactMap { $0 as? NSPopUpButton }
        let filter = menus.first { $0.accessibilityLabel() == "筛选照片分类" }!
        filter.selectItem(withTitle: "普通照片 · 人物与自拍")
        NSApplication.shared.sendAction(filter.action!, to: filter.target, from: filter)
        let bulk = menus.first { $0.accessibilityLabel() == "批量勾选与改类" }!
        assert(bulk.itemTitles.contains("勾选筛选结果"), "A large batch must support approving the current filter without clicking every photo")
        bulk.selectItem(withTitle: "勾选筛选结果")
        NSApplication.shared.sendAction(bulk.action!, to: bulk.target, from: bulk)
        assert(approvals.map { $0.0 } == ["a", "b"] && approvals.allSatisfy { $0.1 },
               "Bulk approval must only include photos in the current filter")
        approvals = []
        bulk.selectItem(withTitle: "取消筛选结果勾选")
        NSApplication.shared.sendAction(bulk.action!, to: bulk.target, from: bulk)
        assert(approvals.map { $0.0 } == ["a", "b"] && approvals.allSatisfy { !$0.1 })
        task.state = .applied
        controller.update(task: task, albums: [])
        assert(!bulk.isEnabled, "Completed tasks must not permit bulk review edits")
        window.close()
    }

    static func confirmationKeepsActionsVisible(_ emptyTask: PhotoClassificationTask) {
        var task = emptyTask
        var writes = 0
        for scheme in [task.ordinaryScheme, task.screenshotScheme] {
            for category in scheme.categories where category.isEnabled {
                let fingerprint = PhotoClassificationFingerprint(
                    assetIdentifier: "synthetic-\(category.id.rawValue)", modificationDate: nil,
                    modelIdentifier: task.modelIdentifier, analyzerVersion: 2,
                    schemeIdentifier: scheme.id, schemeVersion: scheme.version)
                task.assetFingerprints.append(fingerprint)
                task.results.append(.init(fingerprint: fingerprint, categoryIdentifier: category.id, reason: "合成数据"))
                task.approvedAssetIdentifiers.insert(fingerprint.assetIdentifier)
                task.targetsByCategory[category.id] = .newAlbum(name: "合成验证 · \(scheme.name) · \(category.name)")
            }
        }
        let controller = PhotoReviewViewController(task: task, albums: [], thumbnail: { _, _ in nil },
                                                   onAction: { if case .apply = $0 { writes += 1 } })
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 930, height: 658))
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        descendants(controller.view).compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "preview-albums" }!.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let sheet = window.attachedSheet!
        assert(sheet.frame.height <= 560, "Many album targets must scroll, not make the confirmation taller than the window")
        assert(descendants(sheet.contentView!).compactMap { $0 as? NSButton }.contains { $0.title == "加入 19 张照片" },
               "Final confirmation must name the exact number of photos, distinct from previewing the list")
        let cancel = descendants(sheet.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "取消" }!
        let rect = sheet.contentView!.convert(cancel.bounds, from: cancel)
        assert(rect.minY >= 0 && rect.maxY <= sheet.contentView!.bounds.height, "Cancel must stay in the confirmation viewport")
        cancel.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        assert(writes == 0)
        window.close()
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
