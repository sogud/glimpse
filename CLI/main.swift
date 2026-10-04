import Foundation
import GlimpsePhotosCLIKit

enum CLIError: LocalizedError {
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .confirmationRequired: return "未确认写入，照片图库没有改变"
        }
    }

    static let help = """
    用法：
      glimpse photos classify-selection [--limit 10] [--model <model-id>] [--endpoint <url>] [--output <file>] [--json]
      glimpse photos classify-next [--limit 10] [--model <model-id>] [--endpoint <url>] [--output <file>] [--json]
      glimpse photos apply <plan.json>
      glimpse photos status [--json]
      glimpse photos retry <failed|skipped> [--json]

    使用步骤：
      1. 运行 classify-next，从上次进度继续检查最多 10 个图库项目并分析其中的静态照片。
      2. classify-selection 仍可只处理你在「照片」App 中选择的照片。
      3. 检查结果后运行 apply；照片会加入 Glimpse 文件夹下的分类相册。
      4. “待删除”只表示候选相册，CLI 不会删除照片。
      5. status 查看本机分类进度和写入回执，不查询图库总数。
    """
}

@main
struct GlimpseCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        let options = try PhotoLibraryCLIOptions.parse(arguments)
        switch options.command {
        case .classifySelection:
            try await classify(options, source: .selection)
        case .classifyNext:
            try await classify(options, source: .nextBatch)
        case .apply:
            try apply(options.plan!)
        case .status:
            try status(json: options.json)
        case .retry:
            let workspace = PhotoLibraryWorkspace.current
            let lease = try workspace.acquireLock()
            defer { withExtendedLifetime(lease) {} }
            var state = try workspace.loadState()
            let count = state.retry(options.retryOutcome!)
            try workspace.saveState(state)
            if options.json { print("{\"requeued\":\(count)}") }
            else { print("已重新排队 \(count) 个项目；再次运行 classify-next 开始处理。") }
        case .help:
            print(CLIError.help)
        }
    }

    private enum ClassificationSource: Equatable {
        case selection
        case nextBatch
    }

    private struct ClassificationRun {
        let plan: PhotoLibraryClassificationPlan
        let batchState: PhotoLibraryBatchState
        let skippedCount: Int
    }

    private static func classify(_ options: PhotoLibraryCLIOptions, source: ClassificationSource) async throws {
        let limit = options.limit
        let endpoint = options.endpoint
        let jsonOutput = options.json
        let workspace = PhotoLibraryWorkspace.current
        let lease = try workspace.acquireLock()
        defer { withExtendedLifetime(lease) {} }
        let outputURL = planOutputURL(explicitPath: options.output)
        try PhotoLibraryPlanStore.prepareDestination(outputURL)

        if !jsonOutput {
            let sourceText = source == .selection ? "导出当前选择" : "读取下一批"
            print("正在从「照片」\(sourceText)（最多 \(limit) 项）…")
        }
        let service = PhotoLibraryClassificationService()
        let progress: @Sendable (Int, Int, String) -> Void = { current, total, filename in
            guard !jsonOutput else { return }
            print("[\(current)/\(total)] 分析 \(filename)")
        }
        let run: ClassificationRun
        switch source {
        case .selection:
            let selection = try await service.classifySelection(
                limit: limit,
                requestedModel: options.model,
                endpoint: endpoint,
                progress: progress
            )
            var state = try workspace.loadState()
            state.record(selection.plan.items)
            state.recordSkippedAssetIdentifiers(selection.skippedAssetIdentifiers)
            run = ClassificationRun(plan: selection.plan, batchState: state, skippedCount: selection.skippedAssetIdentifiers.count)
        case .nextBatch:
            var state = try workspace.loadState()
            let result = try await service.classifyNextBatch(
                excluding: state.processedAssetIdentifiers,
                limit: limit,
                requestedModel: options.model,
                endpoint: endpoint,
                progress: progress
            )
            switch result {
            case .complete:
                state.markComplete()
                try workspace.saveState(state)
                if jsonOutput {
                    print("{\"completed\":true,\"processed\":0}")
                } else {
                    print("本次扫描没有发现新的待处理项目；这不代表全部分类或写入成功。")
                    print("运行 glimpse photos status 查看失败、跳过及写入回执。")
                }
                return
            case .skipped(let identifiers):
                state.recordSkippedAssetIdentifiers(identifiers)
                try workspace.saveState(state)
                if jsonOutput {
                    print("{\"completed\":false,\"processed\":0,\"skipped\":\(identifiers.count)}")
                } else {
                    print("本批跳过了 \(identifiers.count) 个视频或 Photos 无法导出的项目；下次会继续后面的照片。")
                }
                return
            case .classified(let plan, let skippedAssetIdentifiers):
                state.record(plan.items)
                state.recordSkippedAssetIdentifiers(skippedAssetIdentifiers)
                run = ClassificationRun(plan: plan, batchState: state, skippedCount: skippedAssetIdentifiers.count)
            }
        }

        try PhotoLibraryPlanStore.save(run.plan, to: outputURL)
        try workspace.saveState(run.batchState)

        if jsonOutput {
            let response: [String: Any] = [
                "plan": outputURL.path,
                "model": run.plan.modelIdentifier,
                "processed": run.plan.items.count,
                "classified": run.plan.items.filter { $0.analysisSucceeded && $0.categoryIdentifier != nil }.count,
                "needsReview": run.plan.items.filter { $0.analysisSucceeded && $0.categoryIdentifier == nil }.count,
                "failed": run.plan.items.filter { !$0.analysisSucceeded }.count,
                "skipped": run.skippedCount,
                "albumWriteStatus": "notApplied"
            ]
            let responseData = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
            print(String(decoding: responseData, as: UTF8.self))
            return
        }

        print("")
        for item in run.plan.items {
            let label = item.analysisSucceeded ? (item.categoryName ?? "待分类") : "分析失败"
            print("\(item.filename) → \(label)：\(item.reason)")
        }
        if run.skippedCount > 0 {
            print("本批另有 \(run.skippedCount) 个视频或无法导出的项目被跳过。")
        }
        print("\n分类计划已保存：\(outputURL.path)")
        print("当前没有修改照片图库。确认后运行：")
        print("glimpse photos apply \"\(outputURL.path)\"")
    }

    private static func status(json: Bool) throws {
        let workspace = PhotoLibraryWorkspace.current
        let progress = try workspace.loadState().progress
        let receipts = try workspace.receipts()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let response = StatusResponse(progress: progress, receipts: receipts.map(ReceiptSummary.init))
            print(String(decoding: try encoder.encode(response), as: UTF8.self))
            return
        }
        print("本机分类进度（不是图库总数）：")
        print("已分类：\(progress.classified)；待分类：\(progress.needsReview)；跳过：\(progress.skipped)")
        print("等待重试：\(progress.retryPending)；失败三次：\(progress.failed)")
        print("下次去重跳过的 ID：\(progress.excludedFromNextBatch)；上次扫描已到结尾：\(progress.scanComplete)")
        for receipt in receipts {
            print("计划 \(receipt.plan.id)：已确认 \(receipt.confirmedAssetCount) 张；写入完成：\(receipt.isComplete)")
        }
    }

    private struct StatusResponse: Encodable {
        let progress: PhotoLibraryBatchProgress
        let receipts: [ReceiptSummary]
    }

    private struct ReceiptSummary: Encodable {
        let planID: UUID
        let confirmedAssetCount: Int
        let isComplete: Bool
        let confirmedAlbums: Int
        let unknownAlbums: Int
        let pendingAlbums: Int

        init(_ receipt: PhotoLibraryApplyReceipt) {
            planID = receipt.plan.id
            confirmedAssetCount = receipt.confirmedAssetCount
            isComplete = receipt.isComplete
            confirmedAlbums = receipt.albums.filter { $0.status == .confirmed }.count
            unknownAlbums = receipt.albums.filter { $0.status == .unknown }.count
            pendingAlbums = receipt.albums.filter { $0.status == .pending }.count
        }
    }

    private static func apply(_ path: String) throws {
        let planURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let handle = try FileHandle(forReadingFrom: planURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard data.count <= 1024 * 1024 else { throw PhotoLibraryCLIUsageError("计划文件超过 1 MiB，请分批处理") }
        let plan = try decoder.decode(PhotoLibraryClassificationPlan.self, from: data)
        let additions = try plan.validatedAlbumAdditions()
        guard !additions.isEmpty else {
            print("没有可写入的分类结果。")
            return
        }

        print("将把 \(additions.reduce(0) { $0 + $1.assetIdentifiers.count }) 张照片加入以下相册：")
        for addition in additions {
            print("- \(addition.folderName)/\(addition.albumName)：\(addition.assetIdentifiers.count) 张")
        }
        print("输入 yes 确认：", terminator: "")
        guard readLine()?.lowercased() == "yes" else { throw CLIError.confirmationRequired }

        let receipt = try PhotoLibraryWorkspace.current.apply(plan: plan)
        let skippedCount = additions.reduce(0) { $0 + $1.assetIdentifiers.count } - receipt.confirmedAssetCount
        print("已完成：\(receipt.confirmedAssetCount) 张照片已确认在 Glimpse 分类相册，\(skippedCount) 张已不存在。")
        print("写入回执已保存。再次 apply 同一计划会跳过已经确认的相册。")
        print("原照片没有删除或移动。")
    }

    private static func planOutputURL(explicitPath: String?) -> URL {
        if let explicitPath {
            let url = URL(fileURLWithPath: NSString(string: explicitPath).expandingTildeInPath)
            return url
        }
        let directory = PhotoLibraryWorkspace.current.directory.appendingPathComponent("Plans", isDirectory: true)
        let filename = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-") + "-\(UUID().uuidString).json"
        return directory.appendingPathComponent(filename)
    }
}
