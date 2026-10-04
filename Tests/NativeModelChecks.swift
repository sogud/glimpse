import Foundation

@main
struct NativeModelChecks {
    static func main() async throws {
        let endpoint = URL(string: ProcessInfo.processInfo.environment["GLIMPSE_TEST_ENDPOINT"]!)!
        let client = try LMStudioClient(endpoint: endpoint.appendingPathComponent("native-error"))
        do {
            _ = try await client.classify(jpegData: Data("synthetic".utf8), ocrText: nil,
                                          scheme: .ordinaryDefault, modelIdentifier: "test")
            fatalError("模型错误必须保留")
        } catch {
            precondition(error.localizedDescription.contains("MODEL_NOT_LOADED"))
        }
        let ready = try LMStudioClient(endpoint: endpoint.appendingPathComponent("success"))
        let models = try await ready.visionModels()
        precondition(models.map(\.key) == ["fixture-vision", "unloaded-vision"],
                     "模型列表只提供声明支持视觉的模型，不把文本模型或 embedding 当成识图模型")
        precondition(LMStudioConnectionState.connected(models).loadedModelIdentifiers == ["test"],
                     "只有真实加载的实例可以运行，不能把下载 key 当作已加载模型 ID")
        try await ready.ensureReady(modelIdentifier: "test")
        do {
            try await ready.ensureReady(modelIdentifier: "not-loaded")
            fatalError("未加载的模型不能当作就绪，也不能自动运行 lms")
        } catch LMStudioError.modelNotLoaded(let identifier) {
            precondition(identifier == "not-loaded")
        }
        precondition(LMStudioConnectionState.connected([]).loadedModelIdentifiers.isEmpty,
                     "服务已启动但没有加载模型必须独立表示")
        print("Native model checks passed")
    }
}
