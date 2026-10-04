import Foundation

@main
struct NativeGUIWorkflowChecks {
    static func main() throws {
        try nextBatchExcludesCompletedAndReservedPhotos()
        try wholeLibraryTaskKeepsItsBatchAndReportsProgress()
        try reviewCanExplicitlyClearTheSuggestedCategory()
        try writeConfirmationContainsOnlyApprovedAdditions()
        reviewHonorsTaskStateAndScheme()
        deletionCandidatesShareOneExplicitAlbum()
        print("Native GUI workflow checks passed")
    }

    static func fingerprint(_ identifier: String, version: Int = 1) -> PhotoClassificationFingerprint {
        PhotoClassificationFingerprint(
            assetIdentifier: identifier, modificationDate: nil, modelIdentifier: "fixture-vision",
            analyzerVersion: 2, schemeIdentifier: PhotoClassificationScheme.ordinaryDefault.id,
            schemeVersion: version
        )
    }

    static func nextBatchExcludesCompletedAndReservedPhotos() throws {
        let completed = PhotoClassificationResult(
            fingerprint: fingerprint("a"), categoryIdentifier: "ordinary:pets",
            reason: "synthetic"
        )
        let next = try PhotoClassificationPlanner.nextBatch(
            current: [fingerprint("a"), fingerprint("b"), fingerprint("c"), fingerprint("d")],
            cached: [completed, completed], reserved: [fingerprint("b")], limit: 1
        )
        precondition(next.map(\.assetIdentifier) == ["c"],
                     "下一批跳过已有结果和未完成任务，只选请求数量")
        let changed = try PhotoClassificationPlanner.nextBatch(
            current: [fingerprint("a", version: 2)], cached: [completed], reserved: [], limit: 10
        )
        precondition(changed.map(\.assetIdentifier) == ["a"], "方案变化必须重新分析")
        do {
            _ = try PhotoClassificationPlanner.nextBatch(current: [], cached: [], reserved: [], limit: 101)
            preconditionFailure("单批超过 100 张必须拒绝")
        } catch {}
    }

    static func wholeLibraryTaskKeepsItsBatchAndReportsProgress() throws {
        var task = PhotoClassificationTask(
            id: UUID(), title: "全图库下一批", source: .allPhotos, state: .paused,
            modelIdentifier: "fixture-vision", ordinaryScheme: .ordinaryDefault, screenshotScheme: .screenshotDefault,
            assetFingerprints: [fingerprint("a"), fingerprint("b"), fingerprint("c")],
            results: [
                .init(fingerprint: fingerprint("a"), categoryIdentifier: "ordinary:pets", reason: "synthetic"),
                .init(fingerprint: fingerprint("b"), categoryIdentifier: nil, reason: "uncertain")
            ],
            targetsByCategory: [:], approvedAssetIdentifiers: [], mutations: [], createdAt: Date(), updatedAt: Date()
        )
        precondition(task.progress.total == 3 && task.progress.analyzed == 2
                     && task.progress.classified == 1 && task.progress.needsReview == 1
                     && task.progress.remaining == 1, "分析、待分类和未分析数量必须区分")
        precondition(task.state.reservesPhotos, "未完成的任务继续占用其照片")
        task.state = .closed
        precondition(!task.state.reservesPhotos, "关闭任务后释放未分析照片")
        let decoded = try JSONDecoder().decode(PhotoClassificationTask.self, from: JSONEncoder().encode(task))
        precondition(decoded.source == .allPhotos && decoded.assetFingerprints.map(\.assetIdentifier) == ["a", "b", "c"],
                     "重新读取任务必须保留固定批次")
        task.refreshBatch([fingerprint("a", version: 2), fingerprint("c"), fingerprint("new-photo")])
        precondition(task.assetFingerprints.map(\.assetIdentifier) == ["a", "c"] && task.results.isEmpty,
                     "继续仅刷新固定 ID：不纳入新照片、移除缺失照片、重新分析变更照片")
    }

    static func reviewCanExplicitlyClearTheSuggestedCategory() throws {
        var result = PhotoClassificationResult(
            fingerprint: fingerprint("a"), categoryIdentifier: "ordinary:pets",
            reason: "synthetic"
        )
        result.review = .manual(nil)
        if result.effectiveCategoryIdentifier != nil {
            throw NSError(domain: "NativeGUIWorkflowChecks", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "明确改为待分类后，不能回退到模型建议类别"])
        }
        let decoded = try JSONDecoder().decode(PhotoClassificationResult.self, from: JSONEncoder().encode(result))
        precondition(decoded.effectiveCategoryIdentifier == nil, "明确待分类必须持久保存")
    }

    static func writeConfirmationContainsOnlyApprovedAdditions() throws {
        var task = PhotoClassificationTask(
            id: UUID(), title: "复核", source: .allPhotos, state: .readyForReview,
            modelIdentifier: "fixture-vision", ordinaryScheme: .ordinaryDefault, screenshotScheme: .screenshotDefault,
            assetFingerprints: [fingerprint("a"), fingerprint("b"), fingerprint("c")],
            results: [
                .init(fingerprint: fingerprint("a"), categoryIdentifier: "ordinary:pets", reason: "synthetic"),
                .init(fingerprint: fingerprint("b"), categoryIdentifier: nil, reason: "uncertain"),
                .init(fingerprint: fingerprint("c"), categoryIdentifier: "ordinary:food", reason: "skip target")
            ],
            targetsByCategory: ["ordinary:pets": .newAlbum(name: "普通照片·宠物"), "ordinary:food": .skip],
            approvedAssetIdentifiers: ["a", "b", "c"], mutations: [], createdAt: Date(), updatedAt: Date()
        )
        let confirmation = task.writeConfirmation!
        precondition(confirmation.additions.map(\.assetIdentifier) == ["a"]
                     && confirmation.albumCounts[.newAlbum(name: "普通照片·宠物")] == 1,
                     "确认列表只包含批准、有分类且非跳过的照片")
        precondition(confirmation.matches(task), "未变化的复核快照可确认")
        task.results[0].review = .manual(nil)
        precondition(task.writeConfirmation == nil && !confirmation.matches(task),
                     "没有可写项时禁用写入，复核变更后旧确认失效")
        task.results[0].review = .modelSuggestion
        task.state = .applied
        precondition(task.writeConfirmation == nil, "非复核状态不能重复写入")
    }

    static func reviewHonorsTaskStateAndScheme() {
        var task = PhotoClassificationTask(
            id: UUID(), title: "复核", source: .allPhotos, state: .readyForReview,
            modelIdentifier: "fixture-vision", ordinaryScheme: .ordinaryDefault, screenshotScheme: .screenshotDefault,
            assetFingerprints: [fingerprint("a")],
            results: [.init(fingerprint: fingerprint("a"), categoryIdentifier: "ordinary:pets", reason: "synthetic")],
            targetsByCategory: [:], approvedAssetIdentifiers: ["a"], mutations: [], createdAt: Date(), updatedAt: Date()
        )
        precondition(task.reviewCategory(assetIdentifier: "a", categoryIdentifier: nil)
                     && task.results[0].effectiveCategoryIdentifier == nil && task.approvedAssetIdentifiers.isEmpty,
                     "改为待分类必须取消写入勾选")
        precondition(!task.reviewCategory(assetIdentifier: "a", categoryIdentifier: "screenshot:social"),
                     "普通照片不能混入截图方案")
        task.state = .applied
        precondition(!task.reviewCategory(assetIdentifier: "a", categoryIdentifier: "ordinary:pets")
                     && task.results[0].effectiveCategoryIdentifier == nil, "终态复核只读")
    }

    static func deletionCandidatesShareOneExplicitAlbum() {
        let ordinary = PhotoClassificationScheme.ordinaryDefault
        let screenshot = PhotoClassificationScheme.screenshotDefault
        precondition(ordinary.categories.contains(where: { $0.id == "ordinary:delete-candidates" })
                     && screenshot.categories.contains(where: { $0.id == "screenshot:delete-candidates" }),
                     "两种方案都需要待删除候选，而不是自动删除")
        let targets = PhotoClassificationPlanner.defaultTargets(schemes: [ordinary, screenshot], existingAlbums: [])
        precondition(targets["ordinary:delete-candidates"] == .newAlbum(name: "待删除")
                     && targets["screenshot:delete-candidates"] == .newAlbum(name: "待删除"), "待删除使用同一相册")
        let existing = [PhotoAlbumDescriptor(id: "fixture-album", name: "待删除", assetCount: 2)]
        let reused = PhotoClassificationPlanner.defaultTargets(schemes: [ordinary, screenshot], existingAlbums: existing)
        precondition(reused["ordinary:delete-candidates"] == .existingAlbum(identifier: "fixture-album", name: "待删除"),
                     "唯一同名相册必须复用")
        let ambiguous = PhotoClassificationPlanner.defaultTargets(
            schemes: [ordinary], existingAlbums: existing + [PhotoAlbumDescriptor(id: "other", name: "待删除", assetCount: 0)]
        )
        precondition(ambiguous["ordinary:delete-candidates"] == .skip, "同名相册歧义不能猜测目标")
    }
}
