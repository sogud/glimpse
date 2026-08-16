import Foundation

public enum GlimpsePhotosCLIError: LocalizedError {
    case commandFailed(String)
    case noPhotosSelected
    case noExportedPhotos
    case invalidEndpoint
    case noVisionModel
    case invalidResponse
    case modelOutput(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .noPhotosSelected:
            return "请先在 macOS「照片」App 中选择 1 到 10 张照片"
        case .noExportedPhotos:
            return "所选项目中没有可分析的照片"
        case .invalidEndpoint:
            return "LM Studio 地址必须是 localhost 或本机回环地址"
        case .noVisionModel:
            return "LM Studio 没有运行可识图模型，请先加载 Qwen3-VL 或用 --model 指定"
        case .invalidResponse:
            return "LM Studio 返回了无法识别的响应"
        case .modelOutput(let message):
            return "模型分类结果无效：\(message)"
        }
    }
}

enum CommandRunner {
    static func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GlimpsePhotosCLIError.commandFailed(
                message?.isEmpty == false ? message! : "命令执行失败：\(executable)"
            )
        }
        return outputData
    }
}
