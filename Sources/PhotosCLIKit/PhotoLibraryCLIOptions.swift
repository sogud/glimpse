import Foundation

public struct PhotoLibraryCLIOptions: Equatable, Sendable {
    public enum Command: String, Sendable {
        case classifySelection = "classify-selection"
        case classifyNext = "classify-next"
        case apply, status, retry, help
    }

    public let command: Command
    public private(set) var limit = 10
    public private(set) var endpoint = URL(string: "http://127.0.0.1:1234/v1")!
    public private(set) var model: String?
    public private(set) var output: String?
    public private(set) var plan: String?
    public private(set) var json = false
    public private(set) var retryOutcome: PhotoLibraryBatchOutcome?

    public static func parse(_ arguments: [String]) throws -> Self {
        if arguments.isEmpty || arguments == ["help"] || arguments == ["--help"] || arguments == ["-h"] {
            return Self(command: .help)
        }
        guard arguments.first == "photos", arguments.count >= 2 else {
            throw PhotoLibraryCLIUsageError("请使用 glimpse photos <command>")
        }
        if arguments.count == 2 && ["help", "--help", "-h"].contains(arguments[1]) {
            return Self(command: .help)
        }
        guard let command = Command(rawValue: arguments[1]), command != .help else {
            throw PhotoLibraryCLIUsageError("未知命令：\(arguments[1])")
        }
        let tail = Array(arguments.dropFirst(2))
        if tail == ["--help"] || tail == ["-h"] { return Self(command: .help) }
        var result = Self(command: command)
        if command == .retry {
            guard tail.count == 1 || tail.count == 2,
                  tail.count == 1 || tail[1] == "--json",
                  let outcome = PhotoLibraryBatchOutcome(rawValue: tail[0]),
                  outcome == .failed || outcome == .skipped else {
                throw PhotoLibraryCLIUsageError("retry 只接受 failed 或 skipped，可追加 --json")
            }
            result.retryOutcome = outcome
            result.json = tail.count == 2
            return result
        }
        if command == .apply {
            guard tail.count == 1, !tail[0].hasPrefix("-"), !tail[0].isEmpty else {
                throw PhotoLibraryCLIUsageError("apply 需要且只接受一个分类计划路径")
            }
            result.plan = tail[0]
            return result
        }

        let allowed: Set<String> = command == .status
            ? ["--json"] : ["--limit", "--endpoint", "--model", "--output", "--json"]
        var seen: Set<String> = []
        var index = 0
        while index < tail.count {
            let option = tail[index]
            guard allowed.contains(option), seen.insert(option).inserted else {
                throw PhotoLibraryCLIUsageError("未知或重复参数：\(option)")
            }
            if option == "--json" {
                result.json = true
                index += 1
                continue
            }
            guard index + 1 < tail.count, !tail[index + 1].hasPrefix("-"),
                  !tail[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PhotoLibraryCLIUsageError("\(option) 缺少值")
            }
            let value = tail[index + 1]
            switch option {
            case "--limit":
                guard let limit = Int(value), 1...PhotosAutomation.maximumExportCount ~= limit else {
                    throw PhotoLibraryCLIUsageError("--limit 必须是 1 到 \(PhotosAutomation.maximumExportCount)")
                }
                result.limit = limit
            case "--endpoint":
                guard let endpoint = URL(string: value) else { throw GlimpsePhotosCLIError.invalidEndpoint }
                _ = try LMStudioVisionClient(endpoint: endpoint)
                result.endpoint = endpoint
            case "--model": result.model = value
            case "--output": result.output = value
            default: break
            }
            index += 2
        }
        return result
    }
}

public struct PhotoLibraryCLIUsageError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}
