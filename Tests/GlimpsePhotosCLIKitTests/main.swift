import Foundation
import GlimpsePhotosCLIKit

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("检查失败：\(message)\n".utf8))
        exit(1)
    }
}

expect(PhotosAutomation.maximumExportCount == 10, "单批最多导出 10 张，避免 Photos 长连接失效")

expect(
    PhotoLibrarySelection.schemeKind(filename: "Screenshot 2026.png", width: 1179, height: 2556) == .screenshot,
    "英文截图文件名应使用截图提示"
)
expect(
    PhotoLibrarySelection.schemeKind(filename: "屏幕快照 2026.png", width: 1179, height: 2556) == .screenshot,
    "中文截图文件名应使用截图提示"
)
expect(
    PhotoLibrarySelection.schemeKind(filename: "IMG_1234.HEIC", width: 4032, height: 3024) == .ordinary,
    "普通相机文件名不应误判为截图"
)
expect(
    PhotoClassificationCatalog.ordinary.categories.contains { $0.identifier == "ordinary:delete-candidate" }
        && PhotoClassificationCatalog.screenshot.categories.contains { $0.identifier == "screenshot:delete-candidate" },
    "普通照片和截图都应提供保守的待删除候选分类"
)
expect(
    PhotoClassificationCatalog.schemeKind(forCategoryIdentifier: "ordinary:pets") == .ordinary
        && PhotoClassificationCatalog.schemeKind(forCategoryIdentifier: "screenshot:social") == .screenshot
        && PhotoClassificationCatalog.schemeKind(forCategoryIdentifier: "unknown") == nil,
    "一次模型请求返回的分类 ID 应能可靠确定普通照片或截图方案"
)

let ordinaryPhoto = SelectedPhoto(
    identifier: "asset-1",
    filename: "IMG_1234.HEIC",
    width: 4032,
    height: 3024,
    exportedURL: URL(fileURLWithPath: "/tmp/IMG_1234.jpeg")
)
let petCategory = PhotoClassificationCatalog.ordinary.categories[1]
let ordinaryPlan = PhotoLibraryClassificationPlan(
    modelIdentifier: "qwen/qwen3-vl-4b",
    items: [
        PhotoLibraryClassificationItem(
            photo: ordinaryPhoto,
            categoryIdentifier: petCategory.identifier,
            categoryName: petCategory.name,
            reason: "画面主体是一只猫"
        )
    ]
)
expect(
    ordinaryPlan.albumAdditions == [
        PhotoLibraryAlbumAddition(
            folderName: "Glimpse",
            albumName: "普通照片·宠物",
            assetIdentifiers: ["asset-1"]
        )
    ],
    "普通照片应生成独立的分类相册计划"
)

let screenshotPhoto = SelectedPhoto(
    identifier: "asset-2",
    filename: "IMG_5678.PNG",
    width: 1179,
    height: 2556,
    exportedURL: URL(fileURLWithPath: "/tmp/IMG_5678.jpeg")
)
let screenshotCategory = PhotoClassificationCatalog.screenshot.categories[0]
let screenshotItem = PhotoLibraryClassificationItem(
    photo: screenshotPhoto,
    categoryIdentifier: screenshotCategory.identifier,
    categoryName: screenshotCategory.name,
    reason: "画面是聊天记录"
)
expect(screenshotItem.schemeKind == .screenshot, "模型分类应覆盖无提示作用的文件名")

let deleteCandidatePlan = PhotoLibraryClassificationPlan(
    modelIdentifier: "qwen/qwen3-vl-4b",
    items: [
        PhotoLibraryClassificationItem(
            photo: screenshotPhoto,
            schemeKind: .screenshot,
            categoryIdentifier: "screenshot:delete-candidate",
            categoryName: "待删除",
            reason: "空白误触截图"
        )
    ]
)
expect(
    deleteCandidatePlan.albumAdditions == [
        PhotoLibraryAlbumAddition(folderName: "Glimpse", albumName: "待删除", assetIdentifiers: ["asset-2"])
    ],
    "所有待删除候选都应进入统一相册，且计划本身不删除照片"
)

var batchState = PhotoLibraryBatchState()
batchState.record(ordinaryPlan.items)
expect(batchState.processedAssetIdentifiers == ["asset-1"], "成功分类后应按稳定资源 ID 记录进度")

let failedItem = PhotoLibraryClassificationItem(
    photo: screenshotPhoto,
    categoryIdentifier: nil,
    categoryName: nil,
    reason: "模型暂时不可用",
    analysisSucceeded: false
)
batchState.record([failedItem])
batchState.record([failedItem])
expect(!batchState.processedAssetIdentifiers.contains("asset-2"), "失败照片应自动重试")
batchState.record([failedItem])
expect(batchState.processedAssetIdentifiers.contains("asset-2"), "连续失败三次后应转为待人工确认")
batchState.markComplete()
expect(batchState.isComplete, "扫描完图库后应保存完成状态")
batchState.recordSkippedAssetIdentifiers(["video-1"])
expect(
    batchState.processedAssetIdentifiers.contains("video-1") && !batchState.isComplete,
    "视频或不可导出的项目应被稳定跳过，不能反复卡住图库批处理"
)

let unclassifiedPlan = PhotoLibraryClassificationPlan(
    modelIdentifier: "qwen/qwen3-vl-4b",
    items: [
        PhotoLibraryClassificationItem(
            photo: ordinaryPhoto,
            categoryIdentifier: nil,
            categoryName: nil,
            reason: "无法可靠判断"
        )
    ]
)
expect(unclassifiedPlan.albumAdditions.isEmpty, "待分类项目不应写入相册")

print("Glimpse Photos CLI checks passed")
