import Foundation

public struct PhotoLibraryBatchState: Codable, Equatable, Sendable {
    public private(set) var processedAssetIdentifiers: Set<String>
    public private(set) var failureCountsByAssetIdentifier: [String: Int]
    public private(set) var isComplete: Bool

    public init(
        processedAssetIdentifiers: Set<String> = [],
        failureCountsByAssetIdentifier: [String: Int] = [:],
        isComplete: Bool = false
    ) {
        self.processedAssetIdentifiers = processedAssetIdentifiers
        self.failureCountsByAssetIdentifier = failureCountsByAssetIdentifier
        self.isComplete = isComplete
    }

    public mutating func record(_ items: [PhotoLibraryClassificationItem]) {
        isComplete = false
        for item in items {
            if item.analysisCompletedSuccessfully {
                processedAssetIdentifiers.insert(item.assetIdentifier)
                failureCountsByAssetIdentifier.removeValue(forKey: item.assetIdentifier)
            } else {
                let failures = failureCountsByAssetIdentifier[item.assetIdentifier, default: 0] + 1
                failureCountsByAssetIdentifier[item.assetIdentifier] = failures
                if failures >= 3 {
                    processedAssetIdentifiers.insert(item.assetIdentifier)
                }
            }
        }
    }

    public mutating func markComplete() {
        isComplete = true
    }

    public mutating func recordSkippedAssetIdentifiers(_ identifiers: Set<String>) {
        isComplete = false
        processedAssetIdentifiers.formUnion(identifiers)
    }
}

public enum PhotoLibraryBatchResult: Sendable {
    case classified(PhotoLibraryClassificationPlan, skippedAssetIdentifiers: Set<String>)
    case skipped(Set<String>)
    case complete
}
