import Foundation
import PhotoSortSmartCore

enum CLIError: LocalizedError {
    case usage
    case invalidTaskIdentifier
    case invalidRecentDays

    var errorDescription: String? {
        switch self {
        case .usage:
            return Self.help
        case .invalidTaskIdentifier:
            return "任务 ID 无效"
        case .invalidRecentDays:
            return "最近范围只支持 7、30 或 90 天"
        }
    }

    static let help = """
    用法：
      glimpse status [--json]
      glimpse create-recent <7|30|90> [--model <model-key>]
      glimpse continue <task-id>
      glimpse review <task-id>
      glimpse open

    相册写入仍必须在 Glimpse App 中确认。
    """
}
@main
struct GlimpseCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw CLIError.usage }
        switch command {
        case "status":
            try printStatus(json: arguments.contains("--json"))
        case "create-recent":
            guard arguments.count >= 2,
                  let days = Int(arguments[1]),
                  [7, 30, 90].contains(days) else {
                throw CLIError.invalidRecentDays
            }
            let model = value(after: "--model", in: arguments)
            try submit(
                GlimpseControlCommand(
                    action: .createRecent,
                    taskID: nil,
                    recentDays: days,
                    modelIdentifier: model
                )
            )
            print("已请求创建并启动最近 \(days) 天的分类任务。")
        case "continue":
            let taskID = try taskIdentifier(in: arguments)
            try submit(
                GlimpseControlCommand(
                    action: .continueTask,
                    taskID: taskID,
                    recentDays: nil,
                    modelIdentifier: nil
                )
            )
            print("已请求继续任务 \(taskID.uuidString)。")
        case "review":
            let taskID = try taskIdentifier(in: arguments)
            try submit(
                GlimpseControlCommand(
                    action: .reviewTask,
                    taskID: taskID,
                    recentDays: nil,
                    modelIdentifier: nil
                )
            )
            print("已打开任务 \(taskID.uuidString) 的复核页面。")
        case "open":
            try launchApp()
        case "help", "--help", "-h":
            print(CLIError.help)
        default:
            throw CLIError.usage
        }
    }

    private static func printStatus(json: Bool) throws {
        guard FileManager.default.fileExists(atPath: GlimpseControlFiles.statusURL.path) else {
            print(json ? "{\"tasks\":[]}" : "还没有 Glimpse 任务状态；请先启动 App。")
            return
        }
        let data = try Data(contentsOf: GlimpseControlFiles.statusURL)
        let status = try JSONDecoder().decode(GlimpseControlStatus.self, from: data)
        if json {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }
        if status.tasks.isEmpty {
            print("当前没有分类任务。")
        } else {
            for task in status.tasks {
                print("\(task.id.uuidString)  \(task.state)  \(task.processed)/\(task.total)  \(task.title)")
            }
        }
    }

    private static func submit(_ command: GlimpseControlCommand) throws {
        try GlimpseControlInbox().submit(command)
        try launchApp()
    }

    private static func launchApp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", "everthing.GlimpseMac"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "GlimpseCLI",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "无法打开 Glimpse App，请先在 Xcode 运行 GlimpseMac scheme"]
            )
        }
    }

    private static func taskIdentifier(in arguments: [String]) throws -> UUID {
        guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
            throw CLIError.invalidTaskIdentifier
        }
        return id
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
