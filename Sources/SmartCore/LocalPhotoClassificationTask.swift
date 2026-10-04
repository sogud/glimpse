import Foundation

enum PhotoClassificationSourceScope: Codable, Hashable, Sendable {
    case allPhotos
    case album(identifier: String, name: String)
    case dateRange(start: Date, end: Date)
    case recentDays(Int)
}

enum PhotoClassificationTaskState: String, Codable, Hashable, Sendable {
    case draft
    case running
    case paused
    case readyForReview
    case applying
    case interrupted
    case closed
    case applied
    case undone
    case failed

    var canStartOrContinueInference: Bool {
        switch self {
        case .draft, .paused, .readyForReview, .failed:
            true
        case .running, .applying, .interrupted, .closed, .applied, .undone:
            false
        }
    }

    var canDelete: Bool { self != .running && self != .applying && self != .interrupted }
    var canReview: Bool { self == .readyForReview }
    var reservesPhotos: Bool { self != .closed && self != .applied && self != .undone }

    var recoveredAfterInterruption: Self {
        if self == .running { return .paused }
        if self == .applying { return .interrupted }
        return self
    }

    var afterManualInspection: Self { self == .interrupted ? .closed : self }
}

struct PhotoAlbumMutationRecord: Codable, Hashable, Sendable {
    let assetIdentifier: String
    let albumIdentifier: String
    let albumName: String
    let albumWasCreatedByTask: Bool
}

struct PhotoClassificationTask: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let source: PhotoClassificationSourceScope
    var state: PhotoClassificationTaskState
    var modelIdentifier: String
    let ordinaryScheme: PhotoClassificationScheme
    let screenshotScheme: PhotoClassificationScheme
    var assetFingerprints: [PhotoClassificationFingerprint]
    var results: [PhotoClassificationResult]
    var targetsByCategory: [PhotoClassificationCategoryID: PhotoAlbumTarget]
    var approvedAssetIdentifiers: Set<String>
    var mutations: [PhotoAlbumMutationRecord]
    let createdAt: Date
    var updatedAt: Date

    var progress: PhotoClassificationTaskProgress {
        let current = Set(assetFingerprints)
        let analyzed = results.filter { current.contains($0.fingerprint) }
        let classified = analyzed.filter { $0.effectiveCategoryIdentifier != nil }.count
        return PhotoClassificationTaskProgress(
            total: assetFingerprints.count, analyzed: analyzed.count, classified: classified,
            needsReview: analyzed.count - classified, remaining: max(assetFingerprints.count - analyzed.count, 0)
        )
    }

    var writeConfirmation: PhotoClassificationWriteConfirmation? {
        guard state.canReview else { return nil }
        let additions = PhotoAlbumMutationPlanner.additions(
            results: results, approvedAssetIdentifiers: approvedAssetIdentifiers, targetsByCategory: targetsByCategory
        ).sorted { $0.assetIdentifier < $1.assetIdentifier }
        guard !additions.isEmpty else { return nil }
        return PhotoClassificationWriteConfirmation(id: id, additions: additions)
    }

    func scheme(for result: PhotoClassificationResult) -> PhotoClassificationScheme? {
        if result.fingerprint.schemeIdentifier == ordinaryScheme.id { return ordinaryScheme }
        if result.fingerprint.schemeIdentifier == screenshotScheme.id { return screenshotScheme }
        return nil
    }

    @discardableResult
    mutating func reviewCategory(assetIdentifier: String, categoryIdentifier: PhotoClassificationCategoryID?) -> Bool {
        guard state.canReview, let index = results.firstIndex(where: { $0.id == assetIdentifier }),
              let scheme = scheme(for: results[index]) else { return false }
        if let categoryIdentifier,
           !scheme.categories.contains(where: { $0.id == categoryIdentifier && $0.isEnabled }) { return false }
        results[index].review = .manual(categoryIdentifier)
        if categoryIdentifier == nil { approvedAssetIdentifiers.remove(assetIdentifier) }
        else { approvedAssetIdentifiers.insert(assetIdentifier) }
        return true
    }

    mutating func refreshBatch(_ current: [PhotoClassificationFingerprint]) {
        let identifiers = Set(assetFingerprints.map(\.assetIdentifier))
        assetFingerprints = current.filter { identifiers.contains($0.assetIdentifier) }
        let valid = Set(assetFingerprints)
        results.removeAll { !valid.contains($0.fingerprint) }
        approvedAssetIdentifiers.formIntersection(Set(results.map(\.id)))
    }
}

struct PhotoClassificationTaskProgress: Equatable, Sendable {
    let total: Int
    let analyzed: Int
    let classified: Int
    let needsReview: Int
    let remaining: Int
}

struct PhotoClassificationWriteConfirmation: Identifiable, Hashable, Sendable {
    let id: UUID
    let additions: [PhotoAlbumAddition]

    var albumCounts: [PhotoAlbumTarget: Int] {
        var counts: [PhotoAlbumTarget: Int] = [:]
        for addition in additions { counts[addition.target, default: 0] += 1 }
        return counts
    }

    func matches(_ task: PhotoClassificationTask) -> Bool { self == task.writeConfirmation }
}
