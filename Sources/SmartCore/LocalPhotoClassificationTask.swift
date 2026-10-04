import Foundation

enum PhotoClassificationSourceScope: Codable, Hashable, Sendable {
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
}
