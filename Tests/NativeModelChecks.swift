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
        print("Native model checks passed")
    }
}
