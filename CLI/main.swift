import Foundation
import GlimpsePhotosCLIKit

enum CLIError: LocalizedError {
    case usage
    case missingPlan
    case invalidLimit
    case invalidEndpoint
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .usage: return Self.help
        case .missingPlan: return "请提供分类结果 JSON 文件"
        case .invalidLimit: return "--limit 必须是 1 到 \(PhotosAutomation.maximumExportCount)"
        case .invalidEndpoint: return "--endpoint 不是有效地址"
        case .confirmationRequired: return "未确认写入，照片图库没有改变"
        }
    }

    static let help = """
    用法：
      glimpse photos classify-selection [--limit 10] [--model <model-id>] [--endpoint <url>] [--output <file>] [--json]
      glimpse photos classify-next [--limit 10] [--model <model-id>] [--endpoint <url>] [--output <file>] [--json]
      glimpse photos apply <plan.json>

    使用步骤：
      1. 运行 classify-next，自动从上次进度继续处理最多 10 张静态照片。
      2. classify-selection 仍可只处理你在「照片」App 中选择的照片。
      3. 检查结果后运行 apply；照片会加入 Glimpse 文件夹下的分类相册。
      4. “待删除”只表示候选相册，CLI 不会删除照片。
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
        guard arguments.first == "photos", arguments.count >= 2 else {
            if ["help", "--help", "-h"].contains(arguments.first) {
                print(CLIError.help)
                return
            }
            throw CLIError.usage
        }

        switch arguments[1] {
        case "classify-selection":
            try await classify(arguments, source: .selection)
        case "classify-next":
            try await classify(arguments, source: .nextBatch)
        case "apply":
            try apply(arguments)
        default:
            throw CLIError.usage
        }
    }

    private enum ClassificationSource: Equatable {
        case selection
        case nextBatch
    }

    private struct ClassificationRun {
        let plan: PhotoLibraryClassificationPlan
        let batchState: PhotoLibraryBatchState?
    }

    private static func classify(_ arguments: [String], source: ClassificationSource) async throws {
        let limit = Int(value(after: "--limit", in: arguments) ?? "10") ?? 0
        guard 1...PhotosAutomation.maximumExportCount ~= limit else { throw CLIError.invalidLimit }
        let endpointText = value(after: "--endpoint", in: arguments) ?? "http://127.0.0.1:1234/v1"
        guard let endpoint = URL(string: endpointText) else { throw CLIError.invalidEndpoint }
        let jsonOutput = arguments.contains("--json")

        if !jsonOutput {
            let sourceText = source == .selection ? "导出当前选择" : "读取下一批"
            print("正在从「照片」\(sourceText)（最多 \(limit) 张）…")
        }
        let service = PhotoLibraryClassificationService()
        let progress: @Sendable (Int, Int, String) -> Void = { current, total, filename in
            guard !jsonOutput else { return }
            print("[\(current)/\(total)] 分析 \(filename)")
        }
        let run: ClassificationRun
        switch source {
        case .selection:
            let plan = try await service.classifySelection(
                limit: limit,
                requestedModel: value(after: "--model", in: arguments),
                endpoint: endpoint,
                progress: progress
            )
            run = ClassificationRun(plan: plan, batchState: nil)
        case .nextBatch:
            var state = try loadBatchState()
            let result = try await service.classifyNextBatch(
                excluding: state.processedAssetIdentifiers,
                limit: limit,
                requestedModel: value(after: "--model", in: arguments),
                endpoint: endpoint,
                progress: progress
            )
            switch result {
            case .complete:
                state.markComplete()
                try saveBatchState(state)
                if jsonOutput {
                    print("{\"completed\":true,\"processed\":0}")
                } else {
                    print("图库中的静态照片已经全部处理。以后新增照片时可再次运行同一命令。")
                }
                return
            case .skipped(let identifiers):
                state.recordSkippedAssetIdentifiers(identifiers)
                try saveBatchState(state)
                if jsonOutput {
                    print("{\"completed\":false,\"processed\":0,\"skipped\":\(identifiers.count)}")
                } else {
                    print("本批跳过了 \(identifiers.count) 个视频或 Photos 无法导出的项目；下次会继续后面的照片。")
                }
                return
            case .classified(let plan, let skippedAssetIdentifiers):
                state.record(plan.items)
                state.recordSkippedAssetIdentifiers(skippedAssetIdentifiers)
                run = ClassificationRun(plan: plan, batchState: state)
            }
        }

        let outputURL = try planOutputURL(explicitPath: value(after: "--output", in: arguments))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(run.plan)
        try data.write(to: outputURL, options: .atomic)
        if let state = run.batchState {
            try saveBatchState(state)
        }

        if jsonOutput {
            let response: [String: Any] = [
                "plan": outputURL.path,
                "model": run.plan.modelIdentifier,
                "processed": run.plan.items.count,
                "classified": run.plan.items.filter { $0.categoryName != nil }.count
            ]
            let responseData = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
            print(String(decoding: responseData, as: UTF8.self))
            return
        }

        print("")
        for item in run.plan.items {
            print("\(item.filename) → \(item.categoryName ?? "待分类")：\(item.reason)")
        }
        print("\n分类计划已保存：\(outputURL.path)")
        print("当前没有修改照片图库。确认后运行：")
        print("swift run glimpse photos apply \"\(outputURL.path)\"")
    }

    private static func loadBatchState() throws -> PhotoLibraryBatchState {
        let url = batchStateURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PhotoLibraryBatchState()
        }
        return try JSONDecoder().decode(PhotoLibraryBatchState.self, from: Data(contentsOf: url))
    }

    private static func saveBatchState(_ state: PhotoLibraryBatchState) throws {
        try FileManager.default.createDirectory(
            at: batchStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: batchStateURL, options: .atomic)
    }

    private static var batchStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Glimpse/batch-state.json")
    }

    private static func apply(_ arguments: [String]) throws {
        guard arguments.count >= 3 else { throw CLIError.missingPlan }
        let planURL = URL(fileURLWithPath: NSString(string: arguments[2]).expandingTildeInPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let plan = try decoder.decode(PhotoLibraryClassificationPlan.self, from: Data(contentsOf: planURL))
        guard !plan.albumAdditions.isEmpty else {
            print("没有可写入的分类结果。")
            return
        }

        print("将把 \(plan.albumAdditions.reduce(0) { $0 + $1.assetIdentifiers.count }) 张照片加入以下相册：")
        for addition in plan.albumAdditions {
            print("- \(addition.folderName)/\(addition.albumName)：\(addition.assetIdentifiers.count) 张")
        }
        print("输入 yes 确认：", terminator: "")
        guard readLine()?.lowercased() == "yes" else { throw CLIError.confirmationRequired }

        let appliedCount = try PhotoLibraryClassificationService().apply(plan: plan)
        let skippedCount = plan.albumAdditions.reduce(0) { $0 + $1.assetIdentifiers.count } - appliedCount
        print("已完成：\(appliedCount) 张照片已加入 Glimpse 分类相册，\(skippedCount) 张已不存在或被跳过。")
        print("原照片没有删除或移动。")
    }

    private static func planOutputURL(explicitPath: String?) throws -> URL {
        if let explicitPath {
            let url = URL(fileURLWithPath: NSString(string: explicitPath).expandingTildeInPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return url
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Glimpse/Plans", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-") + ".json"
        return directory.appendingPathComponent(filename)
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
