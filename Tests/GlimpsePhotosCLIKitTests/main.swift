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
let ordinaryAdditions = try ordinaryPlan.validatedAlbumAdditions()
expect(
    ordinaryAdditions == [
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
let deletionAdditions = try deleteCandidatePlan.validatedAlbumAdditions()
expect(
    deletionAdditions == [
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
let unclassifiedAdditions = try unclassifiedPlan.validatedAlbumAdditions()
expect(unclassifiedAdditions.isEmpty, "待分类项目不应写入相册")

let mislabeledPlan = PhotoLibraryClassificationPlan(
    modelIdentifier: "test",
    items: [.init(photo: ordinaryPhoto, categoryIdentifier: "ordinary:pets",
                  categoryName: "待删除", reason: "测试不一致的分类")]
)
func expectRejected(_ message: String, _ operation: () throws -> Void) {
    do {
        try operation()
        expect(false, message)
    } catch {}
}

expectRejected("分类 ID 与名称不一致时必须拒绝整个写入计划") {
    _ = try mislabeledPlan.validatedAlbumAdditions()
}
let invalidItems: [PhotoLibraryClassificationItem] = [
    .init(photo: ordinaryPhoto, categoryIdentifier: "unknown", categoryName: "任意名称", reason: "测试"),
    .init(photo: ordinaryPhoto, schemeKind: .screenshot, categoryIdentifier: petCategory.identifier, categoryName: petCategory.name, reason: "测试"),
    .init(photo: ordinaryPhoto, categoryIdentifier: petCategory.identifier, categoryName: petCategory.name, reason: "失败", analysisSucceeded: false),
    .init(photo: ordinaryPhoto, categoryIdentifier: nil, categoryName: "任意名称", reason: "测试")
]
for item in invalidItems {
    expectRejected("无效分类不能生成相册写入") {
        _ = try PhotoLibraryClassificationPlan(modelIdentifier: "test", items: [item]).validatedAlbumAdditions()
    }
}
expectRejected("重复 ID 必须拒绝，不能虚报照片数") {
    _ = try PhotoLibraryClassificationPlan(modelIdentifier: "test", items: ordinaryPlan.items + ordinaryPlan.items).validatedAlbumAdditions()
}

let invalidArguments = [
    ["photos", "classify-next", "--limt", "1"],
    ["photos", "classify-next", "--limit"],
    ["photos", "classify-next", "--model", "--json"],
    ["photos", "classify-next", "--model", "-h"],
    ["photos", "classify-next", "--limit", "11"],
    ["photos", "classify-next", "--limit", "0"],
    ["photos", "classify-next", "--limit", "1", "--limit", "2"],
    ["photos", "classify-next", "--endpoint", "https://example.com/v1"],
    ["photos", "apply"],
    ["photos", "apply", "plan.json", "--yes"],
    ["photos", "status", "--limit", "10"]
]
for arguments in invalidArguments {
    expectRejected("无效参数必须在访问 Photos 之前拒绝：\(arguments)") {
        _ = try PhotoLibraryCLIOptions.parse(arguments)
    }
}
let parsed = try PhotoLibraryCLIOptions.parse(["photos", "classify-next", "--limit", "3", "--model", "qwen", "--json"])
expect(parsed.limit == 3 && parsed.model == "qwen" && parsed.json, "有效参数应保留原值")
let help = try PhotoLibraryCLIOptions.parse(["photos", "apply", "--help"])
expect(help.command == .help, "子命令帮助不能触发 Photos")

expect(batchState.progress.classified == 1 && batchState.progress.failed == 1 && batchState.progress.skipped == 1,
       "分类成功、失败三次和跳过必须分开计数")
var reviewState = PhotoLibraryBatchState()
reviewState.record(unclassifiedPlan.items)
reviewState.record([failedItem])
expect(reviewState.progress.needsReview == 1 && reviewState.progress.retryPending == 1 && reviewState.progress.classified == 0,
       "待分类和等待重试不能计为分类成功")
let oldData = Data(#"{"processedAssetIdentifiers":["old-1","failed-1"],"failureCountsByAssetIdentifier":{"failed-1":3,"retry-1":1},"isComplete":true}"#.utf8)
expectRejected("内部开发版不读取或迁移旧状态格式") {
    _ = try JSONDecoder().decode(PhotoLibraryBatchState.self, from: oldData)
}
let restored = try JSONDecoder().decode(PhotoLibraryBatchState.self, from: JSONEncoder().encode(batchState))
expect(restored == batchState, "新版进度必须无损保存和恢复")
var retryState = batchState
retryState.record([PhotoLibraryClassificationItem(photo: SelectedPhoto(identifier: "pending-1", filename: "pending.jpg", width: 1, height: 1, exportedURL: URL(fileURLWithPath: "/synthetic")), categoryIdentifier: nil, categoryName: nil, reason: "fixture", analysisSucceeded: false)])
let retriedCount = retryState.retry(.failed)
expect(retriedCount == 1 && retryState.processedAssetIdentifiers == ["asset-1", "video-1"],
       "重试失败项只重置失败集合，保留成功和跳过项")
expect(retryState.progress.retryPending == 1, "retry failed 不重置尚在自动重试的项目")
let retriedSkippedCount = retryState.retry(.skipped)
expect(retriedSkippedCount == 1 && retryState.processedAssetIdentifiers == ["asset-1"],
       "显式重试跳过项不会丢失成功分类")
let retryOptions = try PhotoLibraryCLIOptions.parse(["photos", "retry", "failed", "--json"])
expect(retryOptions.command == .retry && retryOptions.retryOutcome == .failed && retryOptions.json,
       "CLI 提供明确的重试集合")

let malformedPhotos = PhotosAutomation { _, _ in Data("not a count".utf8) }
expectRejected("不能把无法解析的 Photos 写入结果当成零张成功") {
    _ = try malformedPhotos.applyAlbum(ordinaryAdditions[0])
}
let largeIdentifiers = Set((0..<20_000).map { "asset-\($0)-" + String(repeating: "x", count: 80) })
let fileBasedPhotos = PhotosAutomation { _, arguments in
    guard arguments.count == 5 else { throw GlimpsePhotosCLIError.commandFailed("去重 ID 不应进入命令行参数") }
    let identifiers = try String(contentsOfFile: arguments[4], encoding: .utf8).split(whereSeparator: \.isNewline)
    guard identifiers.count == 20_000 else { throw GlimpsePhotosCLIError.commandFailed("去重文件不完整") }
    let lookupHeader = arguments[1].components(separatedBy: "on run argv")[0]
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
    compiler.arguments = ["-o", URL(fileURLWithPath: arguments[2]).appendingPathComponent("fixture.scpt").path, "-e", arguments[1]]
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else { throw GlimpsePhotosCLIError.commandFailed("实际导出 AppleScript 编译失败") }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", lookupHeader + "\nset lookup to my excludedIDs(\"asset-2\")\nreturn (lookup's containsObject:\"asset-2\") as boolean"]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let response = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 && response.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
        throw GlimpsePhotosCLIError.commandFailed("排除集合实际 AppleScript 检查失败：\(response)")
    }
    return Data()
}
let emptyLargeBatch = try fileBasedPhotos.exportLibraryBatch(excluding: largeIdentifiers, limit: 10)
expect(emptyLargeBatch.photos.isEmpty, "大图库去重 ID 应经文件传输，不受 argv 大小限制")
emptyLargeBatch.removeTemporaryFiles()
let unusualFilename = "fixture\twith\nline.jpg"
let unusualPhotos = PhotosAutomation { _, arguments in
    let url = URL(fileURLWithPath: arguments[2]).appendingPathComponent("0").appendingPathComponent(unusualFilename)
    try Data().write(to: url)
    return Data("asset-unusual\t1\t1\t0\n".utf8)
}
let unusualBatch = try unusualPhotos.exportSelection(limit: 1)
expect(unusualBatch.photos.first?.filename == unusualFilename && unusualBatch.skippedAssetIdentifiers.isEmpty,
       "带制表符和换行的文件名不能损坏资源元数据")
unusualBatch.removeTemporaryFiles()

let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("glimpse-checks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
let sharedDirectory = fixtureDirectory.appendingPathComponent("shared")
try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: sharedDirectory.path)
expectRejected("共享目录不能用来保存私人运行状态") {
    _ = try PhotoLibraryWorkspace(directory: sharedDirectory).acquireLock()
}
try FileManager.default.removeItem(at: sharedDirectory)
defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
let workspace = PhotoLibraryWorkspace(directory: fixtureDirectory.appendingPathComponent("runtime"))
do {
    let lease = try workspace.acquireLock()
    let otherDirectory = fixtureDirectory.appendingPathComponent("other-runtime")
    expectRejected("不同运行目录也不能同时写入同一个 Photos 图库") {
        _ = try PhotoLibraryWorkspace(directory: otherDirectory).acquireLock()
    }
    try FileManager.default.removeItem(at: otherDirectory)
    expectRejected("同一运行目录的第二个写进程必须拒绝") {
        _ = try PhotoLibraryWorkspace(directory: workspace.directory).acquireLock()
    }
    try workspace.saveState(batchState)
    let statePermissions = try FileManager.default.attributesOfItem(atPath: workspace.directory.appendingPathComponent("state.json").path)[.posixPermissions] as? Int
    expect(statePermissions == 0o600, "状态文件只允许当前用户读写")
    let saved = try workspace.loadState()
    expect(saved == batchState, "工作区状态应通过公开接口恢复")
    withExtendedLifetime(lease) {}
}
do {
    let lease = try workspace.acquireLock()
    withExtendedLifetime(lease) {}
}
let applyPlan = PhotoLibraryClassificationPlan(modelIdentifier: "test", items: ordinaryPlan.items + deleteCandidatePlan.items)
let interruptedPhotos = PhotosAutomation { _, arguments in
    if arguments[3] == "待删除" { return Data("album\talbum-delete\nadded\tasset-2\n".utf8) }
    throw GlimpsePhotosCLIError.commandFailed("synthetic interruption")
}
expectRejected("写入中断必须报告失败并保存回执") {
    _ = try workspace.apply(plan: applyPlan, photos: interruptedPhotos)
}
let interruptedReceipt = try workspace.receipts()[0]
expect(!interruptedReceipt.isComplete && interruptedReceipt.confirmedAssetCount == 1
       && interruptedReceipt.albums.filter { $0.status == .unknown }.count == 1,
       "重启后能区分已确认相册和结果未知的相册")
let resumedPhotos = PhotosAutomation { _, arguments in
    guard arguments[3] == "普通照片·宠物" else { throw GlimpsePhotosCLIError.commandFailed("不应重写已确认相册") }
    return Data("album\talbum-pets\nexisting\tasset-1\n".utf8)
}
let completedReceipt = try workspace.apply(plan: applyPlan, photos: resumedPhotos)
expect(completedReceipt.isComplete && completedReceipt.confirmedAssetCount == 2,
       "继续写入跳过已确认相册，能识别中断前已存在的成员")
let receiptURL = workspace.directory.appendingPathComponent("Receipts/\(applyPlan.id.uuidString).json")
var corruptedReceipt = completedReceipt
corruptedReceipt.albums[0].result = nil
try JSONEncoder().encode(corruptedReceipt).write(to: receiptURL, options: .atomic)
expectRejected("已确认但缺少结果的回执不能被当成成功") {
    _ = try workspace.apply(plan: applyPlan, photos: resumedPhotos)
}
try JSONEncoder().encode(completedReceipt).write(to: receiptURL, options: .atomic)
let changedPlan = PhotoLibraryClassificationPlan(id: applyPlan.id, modelIdentifier: "changed", createdAt: applyPlan.createdAt,
                                                items: applyPlan.items)
expectRejected("不能修改已开始写入的计划") {
    _ = try workspace.apply(plan: changedPlan, photos: resumedPhotos)
}
let oversizedItems = (0..<11).map { index in
    PhotoLibraryClassificationItem(photo: SelectedPhoto(identifier: "many-\(index)", filename: "fixture.jpg", width: 1, height: 1, exportedURL: URL(fileURLWithPath: "/synthetic")), categoryIdentifier: "ordinary:pets", categoryName: "宠物", reason: "fixture")
}
expectRejected("单个计划不能超过批次上限") {
    _ = try PhotoLibraryClassificationPlan(modelIdentifier: "test", items: oversizedItems).validatedAlbumAdditions()
}
let planURL = fixtureDirectory.appendingPathComponent("plan.json")
try PhotoLibraryPlanStore.prepareDestination(planURL)
let preflightFiles = try FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
expect(preflightFiles.sorted() == ["runtime"], "输出路径预检查不能遗留探测文件")
try PhotoLibraryPlanStore.save(ordinaryPlan, to: planURL)
let planPermissions = try FileManager.default.attributesOfItem(atPath: planURL.path)[.posixPermissions] as? Int
expect(planPermissions == 0o600, "分类计划只允许当前用户读写")
expectRejected("输出路径的父级不是目录时应在推理前拒绝") {
    try PhotoLibraryPlanStore.prepareDestination(planURL.appendingPathComponent("child.json"))
}
let originalData = try Data(contentsOf: planURL)
let legacyDecoder = JSONDecoder()
legacyDecoder.dateDecodingStrategy = .iso8601
let legacyText = String(decoding: originalData, as: UTF8.self).replacingOccurrences(of: "\"analysisSucceeded\" : true,", with: "")
expectRejected("计划必须明确说明分析成功状态；不兼容旧格式") {
    _ = try legacyDecoder.decode(PhotoLibraryClassificationPlan.self, from: Data(legacyText.utf8))
}
expectRejected("已存在的计划不能覆盖") { try PhotoLibraryPlanStore.save(deleteCandidatePlan, to: planURL) }
let unchangedData = try Data(contentsOf: planURL)
expect(unchangedData == originalData, "拒绝覆盖后原计划应保持不变")
let danglingURL = fixtureDirectory.appendingPathComponent("dangling.json")
try FileManager.default.createSymbolicLink(at: danglingURL, withDestinationURL: fixtureDirectory.appendingPathComponent("missing.json"))
expectRejected("悬空软链接不能作为新的计划文件") { try PhotoLibraryPlanStore.save(ordinaryPlan, to: danglingURL) }

// 可选的真实 HTTP 协议检查只连接 CLITransportChecks.py 创建的合成本机服务。
if let endpoint = ProcessInfo.processInfo.environment["GLIMPSE_TEST_ENDPOINT"], let base = URL(string: endpoint) {
    let client = try LMStudioVisionClient(endpoint: base.appendingPathComponent("redirect"))
    do {
        _ = try await client.resolveModel(requested: nil)
        expect(false, "本地服务重定向必须拒绝，不能继续请求目标地址")
    } catch {}
    let imageURL = fixtureDirectory.appendingPathComponent("pixel.png")
    let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!
    try pixel.write(to: imageURL)
    do {
        _ = try await client.classify(imageURL: imageURL, filename: "synthetic.png", modelIdentifier: "test")
        expect(false, "图片 POST 请求也不能跟随重定向")
    } catch {}
    let errorClient = try LMStudioVisionClient(endpoint: base.appendingPathComponent("error"))
    do {
        _ = try await errorClient.classify(imageURL: imageURL, filename: "synthetic.png", modelIdentifier: "test")
        expect(false, "HTTP 400 必须报告模型错误")
    } catch {
        expect(error.localizedDescription.contains("MODEL_NOT_LOADED"), "HTTP 400 应保留实际服务错误，不能误报为结构化输出不支持")
    }
    let syntheticPhotos = PhotosAutomation { executable, arguments in
        guard executable == "/usr/bin/osascript", arguments.count == 4 else {
            throw GlimpsePhotosCLIError.commandFailed("unexpected synthetic command")
        }
        let root = URL(fileURLWithPath: arguments[2])
        try pixel.write(to: root.appendingPathComponent("0/pixel.png"))
        return Data("photo-1\t1\t1\t0\nvideo-1\t1\t1\t1\n".utf8)
    }
    let malformedClient = try LMStudioVisionClient(endpoint: base.appendingPathComponent("missing-category"))
    do {
        _ = try await malformedClient.classify(imageURL: imageURL, filename: "synthetic.png", modelIdentifier: "test")
        expect(false, "缺失 category 不是待分类，必须拒绝")
    } catch {}
    do {
        _ = try await PhotoLibraryClassificationService(photos: syntheticPhotos).classifySelection(
            limit: 2, requestedModel: "test", endpoint: base.appendingPathComponent("error")
        )
        expect(false, "模型服务错误必须在导出前阻止分类")
    } catch {
        expect(error.localizedDescription.contains("MODEL_NOT_LOADED"), "服务错误应直接失败而不是生成一批失败计划")
    }
    let selection = try await PhotoLibraryClassificationService(photos: syntheticPhotos).classifySelection(
        limit: 2, requestedModel: "test", endpoint: base.appendingPathComponent("success")
    )
    expect(selection.plan.items.count == 1 && selection.plan.items[0].categoryIdentifier == "ordinary:pets",
           "手选照片应保留实际模型分类结果")
    expect(selection.skippedAssetIdentifiers == ["video-1"], "手选混合媒体不能丢失跳过数量")
}

print("Glimpse Photos CLI checks passed")
