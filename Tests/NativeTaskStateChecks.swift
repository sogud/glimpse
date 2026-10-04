import Foundation

@main
struct NativeTaskStateChecks {
    static func main() throws {
        precondition(PhotoClassificationTaskState.running.recoveredAfterInterruption == .paused,
                     "重启必须能继续中断的推理")
        precondition(PhotoClassificationTaskState.applying.recoveredAfterInterruption == .interrupted,
                     "中断的 Photos 写入必须保持未知，不能卡在 applying 或假报成功")
        precondition(!PhotoClassificationTaskState.running.canDelete && !PhotoClassificationTaskState.applying.canDelete,
                     "活动任务不能删除")
        precondition(PhotoClassificationTaskState.readyForReview.canReview
                     && !PhotoClassificationTaskState.applying.canReview && !PhotoClassificationTaskState.closed.canReview,
                     "写入期间和终态不可更改复核快照")
        precondition(!PhotoClassificationTaskState.interrupted.canStartOrContinueInference,
                     "未知的写入结果不能被重新推理覆盖")
        precondition(PhotoClassificationTaskState.interrupted.afterManualInspection == .closed
                     && !PhotoClassificationTaskState.closed.canStartOrContinueInference,
                     "检查未知操作后只能关闭，不能重复新建相册或误将撤销恢复成写入")
        let targets = PhotoClassificationPlanner.defaultTargets(schemes: [.ordinaryDefault, .screenshotDefault], existingAlbums: [])
        precondition(targets["ordinary:work-study"] == .newAlbum(name: "普通照片·工作学习")
                     && targets["screenshot:work-study"] == .newAlbum(name: "截图·工作学习"),
                     "普通照片和截图同名类别必须有独立相册目标")
        let decoder = PhotoClassificationResponseDecoder(allowedCategoryIdentifiers: [])
        do {
            _ = try decoder.decode(#"{"reason":"fixture"}"#)
            preconditionFailure("缺失 category 必须拒绝")
        } catch {}
        let unknown = try decoder.decode(#"{"category":null,"reason":"fixture"}"#)
        precondition(unknown.categoryIdentifier == nil, "明确 null 是有效的待分类")
        do {
            _ = try JSONDecoder().decode(PhotoClassificationFingerprint.self, from: Data(#"{"assetIdentifier":"fixture","modelIdentifier":"test","analyzerVersion":1,"schemeVersion":1}"#.utf8))
            preconditionFailure("当前格式必须有方案身份，不读取旧缓存")
        } catch {}
        print("Native task-state checks passed")
    }
}
