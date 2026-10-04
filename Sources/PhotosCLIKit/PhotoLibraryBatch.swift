import Foundation

public enum PhotoLibraryBatchOutcome: String, Codable, Sendable {
    case classified, needsReview, skipped, failed
}

public struct PhotoLibraryBatchEntry: Codable, Equatable, Sendable {
    public let outcome: PhotoLibraryBatchOutcome
    public let failures: Int
}

public struct PhotoLibraryBatchState: Codable, Equatable, Sendable {
    public private(set) var entries: [String: PhotoLibraryBatchEntry]
    public private(set) var isComplete: Bool

    public init() {
        entries = [:]
        isComplete = false
    }

    public var processedAssetIdentifiers: Set<String> {
        var identifiers: Set<String> = []
        for (identifier, entry) in entries {
            if entry.outcome != .failed || entry.failures >= 3 {
                identifiers.insert(identifier)
            }
        }
        return identifiers
    }

    public var progress: PhotoLibraryBatchProgress {
        var progress = PhotoLibraryBatchProgress(excludedFromNextBatch: processedAssetIdentifiers.count, scanComplete: isComplete)
        for entry in entries.values {
            switch entry.outcome {
            case .classified: progress.classified += 1
            case .needsReview: progress.needsReview += 1
            case .skipped: progress.skipped += 1
            case .failed:
                if entry.failures >= 3 { progress.failed += 1 }
                else { progress.retryPending += 1 }
            }
        }
        return progress
    }

    public mutating func record(_ items: [PhotoLibraryClassificationItem]) {
        isComplete = false
        for item in items {
            if item.analysisSucceeded {
                let outcome: PhotoLibraryBatchOutcome = item.categoryIdentifier == nil ? .needsReview : .classified
                entries[item.assetIdentifier] = PhotoLibraryBatchEntry(outcome: outcome, failures: 0)
            } else {
                let failures = (entries[item.assetIdentifier]?.failures ?? 0) + 1
                entries[item.assetIdentifier] = PhotoLibraryBatchEntry(outcome: .failed, failures: failures)
            }
        }
    }

    public mutating func markComplete() { isComplete = true }

    @discardableResult
    public mutating func retry(_ outcome: PhotoLibraryBatchOutcome) -> Int {
        let identifiers = entries.filter {
            $0.value.outcome == outcome && (outcome != .failed || $0.value.failures >= 3)
        }.map(\.key)
        for identifier in identifiers { entries.removeValue(forKey: identifier) }
        if !identifiers.isEmpty { isComplete = false }
        return identifiers.count
    }

    public mutating func recordSkippedAssetIdentifiers(_ identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        isComplete = false
        for identifier in identifiers {
            entries[identifier] = PhotoLibraryBatchEntry(outcome: .skipped, failures: 0)
        }
    }
}

public struct PhotoLibraryBatchProgress: Encodable, Equatable, Sendable {
    public let excludedFromNextBatch: Int
    public let scanComplete: Bool
    public var classified = 0
    public var needsReview = 0
    public var skipped = 0
    public var failed = 0
    public var retryPending = 0
}

public enum PhotoLibraryBatchResult: Sendable {
    case classified(PhotoLibraryClassificationPlan, skippedAssetIdentifiers: Set<String>)
    case skipped(Set<String>)
    case complete
}
