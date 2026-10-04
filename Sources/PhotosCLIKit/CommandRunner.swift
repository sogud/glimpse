import Foundation
import Darwin

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
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 120) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("glimpse-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorsURL = directory.appendingPathComponent("stderr")
        try Data().write(to: outputURL)
        try Data().write(to: errorsURL)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorsURL)
        defer { try? output.close(); try? errors.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) != .success {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw GlimpsePhotosCLIError.commandFailed("子进程超时：\(executable)")
        }
        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorsURL)
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData.prefix(8_000), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GlimpsePhotosCLIError.commandFailed(
                message?.isEmpty == false ? message! : "命令执行失败：\(executable)"
            )
        }
        return outputData
    }
}
