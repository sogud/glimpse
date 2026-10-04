import Foundation

public struct PhotoLibraryClassificationService: Sendable {
    private let photos: PhotosAutomation

    public init(photos: PhotosAutomation = PhotosAutomation()) {
        self.photos = photos
    }

    public func classifySelection(
        limit: Int = 10,
        requestedModel: String? = nil,
        endpoint: URL = URL(string: "http://127.0.0.1:1234/v1")!,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) async throws -> (plan: PhotoLibraryClassificationPlan, skippedAssetIdentifiers: Set<String>) {
        let client = try LMStudioVisionClient(endpoint: endpoint)
        let model = try await client.resolveModel(requested: requestedModel)
        let selection = try photos.exportSelection(limit: limit)
        defer { selection.removeTemporaryFiles() }
        let plan = try await classify(
            photos: selection.photos,
            client: client,
            model: model,
            progress: progress
        )
        return (plan, selection.skippedAssetIdentifiers)
    }

    public func classifyNextBatch(
        excluding processedAssetIdentifiers: Set<String>,
        limit: Int = 10,
        requestedModel: String? = nil,
        endpoint: URL = URL(string: "http://127.0.0.1:1234/v1")!,
        progress: @escaping @Sendable (Int, Int, String) -> Void = { _, _, _ in }
    ) async throws -> PhotoLibraryBatchResult {
        let client = try LMStudioVisionClient(endpoint: endpoint)
        let model = try await client.resolveModel(requested: requestedModel)
        let selection = try photos.exportLibraryBatch(
            excluding: processedAssetIdentifiers,
            limit: limit
        )
        defer { selection.removeTemporaryFiles() }
        guard !selection.photos.isEmpty else {
            return selection.skippedAssetIdentifiers.isEmpty
                ? .complete
                : .skipped(selection.skippedAssetIdentifiers)
        }
        let plan = try await classify(
            photos: selection.photos,
            client: client,
            model: model,
            progress: progress
        )
        return .classified(plan, skippedAssetIdentifiers: selection.skippedAssetIdentifiers)
    }

    private func classify(
        photos: [SelectedPhoto],
        client: LMStudioVisionClient,
        model: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> PhotoLibraryClassificationPlan {
        var results: [PhotoLibraryClassificationItem] = []

        for (index, photo) in photos.enumerated() {
            try Task.checkCancellation()
            progress(index + 1, photos.count, photo.filename)
            do {
                let classification = try await client.classify(
                    imageURL: photo.exportedURL,
                    filename: photo.filename,
                    modelIdentifier: model
                )
                let scheme = PhotoClassificationCatalog.scheme(for: classification.schemeKind)
                let category = scheme.categories.first { $0.identifier == classification.categoryIdentifier }
                results.append(
                    PhotoLibraryClassificationItem(
                        photo: photo,
                        schemeKind: classification.schemeKind,
                        categoryIdentifier: category?.identifier,
                        categoryName: category?.name,
                        reason: classification.reason
                    )
                )
            } catch {
                if Task.isCancelled { throw CancellationError() }
                results.append(
                    PhotoLibraryClassificationItem(
                        photo: photo,
                        categoryIdentifier: nil,
                        categoryName: nil,
                        reason: "分析失败：\(error.localizedDescription)",
                        analysisSucceeded: false
                    )
                )
            }
        }
        return PhotoLibraryClassificationPlan(modelIdentifier: model, items: results)
    }

}
