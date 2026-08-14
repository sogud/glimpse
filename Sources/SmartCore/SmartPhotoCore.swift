import Foundation
import SwiftData

@MainActor
enum PhotoSortDataContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(
                for: PhotoDecisionEntity.self,
                SmartAnalysisRecordEntity.self,
                SmartAnalysisMetadataEntity.self,
                PhotoClassificationTaskEntity.self
            )
        } catch {
            fatalError("无法创建本地数据存储: \(error.localizedDescription)")
        }
    }()
}

struct SimilarityCandidate: Hashable, Sendable {
    let id: String
    let capturedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let featureVector: [Float]
    let sharpness: Double
    let faceQuality: Double?
    let estimatedBytes: Int64
}

struct SimilarityCluster: Hashable, Identifiable, Sendable {
    let id: String
    let memberIdentifiers: [String]
    let recommendedKeeperIdentifier: String
    let reviewIdentifiers: [String]
    let recoverableBytes: Int64
    let recommendationReasons: [String]
}

struct SimilarityClusterer: Sendable {
    let maximumTimeGap: TimeInterval
    let maximumFeatureDistance: Float
    let aspectRatioTolerance: Double

    init(
        maximumTimeGap: TimeInterval = 10 * 60,
        maximumFeatureDistance: Float = 0.18,
        aspectRatioTolerance: Double = 0.08
    ) {
        self.maximumTimeGap = maximumTimeGap
        self.maximumFeatureDistance = maximumFeatureDistance
        self.aspectRatioTolerance = aspectRatioTolerance
    }

    func clusters(from candidates: [SimilarityCandidate]) -> [SimilarityCluster] {
        temporalBuckets(from: candidates).flatMap(makeClusters(in:))
    }

    private func temporalBuckets(from candidates: [SimilarityCandidate]) -> [[SimilarityCandidate]] {
        let sorted = candidates.sorted { $0.capturedAt < $1.capturedAt }
        var buckets: [[SimilarityCandidate]] = []

        for candidate in sorted {
            guard let last = buckets.last?.last,
                  candidate.capturedAt.timeIntervalSince(last.capturedAt) <= maximumTimeGap else {
                buckets.append([candidate])
                continue
            }
            buckets[buckets.count - 1].append(candidate)
        }
        return buckets
    }

    private func makeClusters(in bucket: [SimilarityCandidate]) -> [SimilarityCluster] {
        guard bucket.count >= 2 else { return [] }

        var parents = Array(bucket.indices)

        func root(of index: Int) -> Int {
            var current = index
            while parents[current] != current {
                current = parents[current]
            }
            return current
        }

        for leftIndex in bucket.indices {
            for rightIndex in bucket.index(after: leftIndex)..<bucket.endIndex {
                guard areComparable(bucket[leftIndex], bucket[rightIndex]) else { continue }
                guard featureDistance(bucket[leftIndex], bucket[rightIndex]) <= maximumFeatureDistance else { continue }

                let leftRoot = root(of: leftIndex)
                let rightRoot = root(of: rightIndex)
                if leftRoot != rightRoot {
                    parents[rightRoot] = leftRoot
                }
            }
        }

        let grouped = Dictionary(grouping: bucket.indices) { root(of: $0) }
        return grouped.values
            .map { $0.map { bucket[$0] } }
            .filter { $0.count >= 2 }
            .map(makeCluster(from:))
            .sorted { $0.id < $1.id }
    }

    private func areComparable(_ left: SimilarityCandidate, _ right: SimilarityCandidate) -> Bool {
        guard left.pixelHeight > 0, right.pixelHeight > 0 else { return false }
        let leftRatio = Double(left.pixelWidth) / Double(left.pixelHeight)
        let rightRatio = Double(right.pixelWidth) / Double(right.pixelHeight)
        return abs(leftRatio - rightRatio) <= aspectRatioTolerance
    }

    private func featureDistance(_ left: SimilarityCandidate, _ right: SimilarityCandidate) -> Float {
        guard left.featureVector.count == right.featureVector.count,
              !left.featureVector.isEmpty else {
            return .greatestFiniteMagnitude
        }

        let squaredDistance = zip(left.featureVector, right.featureVector).reduce(Float.zero) {
            $0 + pow($1.0 - $1.1, 2)
        }
        return sqrt(squaredDistance)
    }

    private func makeCluster(from members: [SimilarityCandidate]) -> SimilarityCluster {
        let maximumPixels = max(
            members.map { Double($0.pixelWidth * $0.pixelHeight) }.max() ?? 1,
            1
        )
        let keeper = members.max { left, right in
            qualityScore(left, maximumPixels: maximumPixels) < qualityScore(right, maximumPixels: maximumPixels)
        } ?? members[0]
        let memberIdentifiers = members.map(\.id).sorted()
        let reviewIdentifiers = memberIdentifiers.filter { $0 != keeper.id }
        let memberByIdentifier = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })

        return SimilarityCluster(
            id: memberIdentifiers.joined(separator: "|"),
            memberIdentifiers: memberIdentifiers,
            recommendedKeeperIdentifier: keeper.id,
            reviewIdentifiers: reviewIdentifiers,
            recoverableBytes: reviewIdentifiers.reduce(0) {
                $0 + max(memberByIdentifier[$1]?.estimatedBytes ?? 0, 0)
            },
            recommendationReasons: recommendationReasons(for: keeper, in: members)
        )
    }

    private func qualityScore(_ candidate: SimilarityCandidate, maximumPixels: Double) -> Double {
        let pixels = Double(candidate.pixelWidth * candidate.pixelHeight)
        return candidate.sharpness * 0.55
            + (candidate.faceQuality ?? 0) * 0.3
            + (pixels / maximumPixels) * 0.15
    }

    private func recommendationReasons(
        for keeper: SimilarityCandidate,
        in members: [SimilarityCandidate]
    ) -> [String] {
        var reasons = ["清晰度更高"]
        if keeper.faceQuality == members.compactMap(\.faceQuality).max(), keeper.faceQuality != nil {
            reasons.append("人脸质量更好")
        }
        if keeper.pixelWidth * keeper.pixelHeight == members.map({ $0.pixelWidth * $0.pixelHeight }).max() {
            reasons.append("分辨率更高")
        }
        return reasons
    }
}

struct AssetFingerprint: Hashable, Sendable {
    let id: String
    let modificationDate: Date?
    let analyzerVersion: Int
}

struct IncrementalAnalysisPlan: Equatable, Sendable {
    let addedIdentifiers: [String]
    let updatedIdentifiers: [String]
    let deletedIdentifiers: [String]
    let unchangedIdentifiers: [String]

    var identifiersRequiringAnalysis: [String] {
        (addedIdentifiers + updatedIdentifiers).sorted()
    }
}

enum IncrementalAnalysisPlanner {
    static func plan(
        cached: [AssetFingerprint],
        current: [AssetFingerprint]
    ) -> IncrementalAnalysisPlan {
        let cachedByIdentifier = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        let currentByIdentifier = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let cachedIdentifiers = Set(cachedByIdentifier.keys)
        let currentIdentifiers = Set(currentByIdentifier.keys)

        let added = currentIdentifiers.subtracting(cachedIdentifiers).sorted()
        let deleted = cachedIdentifiers.subtracting(currentIdentifiers).sorted()
        var updated: [String] = []
        var unchanged: [String] = []

        for identifier in cachedIdentifiers.intersection(currentIdentifiers).sorted() {
            if cachedByIdentifier[identifier] == currentByIdentifier[identifier] {
                unchanged.append(identifier)
            } else {
                updated.append(identifier)
            }
        }

        return IncrementalAnalysisPlan(
            addedIdentifiers: added,
            updatedIdentifiers: updated,
            deletedIdentifiers: deleted,
            unchangedIdentifiers: unchanged
        )
    }
}

enum PhotoDecisionKind: String, Codable, Hashable, Sendable {
    case permanentKeep
    case reviewLater
    case archived
}

enum CleanupIntent: Hashable, Sendable {
    case deleteCleanup
    case organize
}

struct PhotoDecision: Codable, Hashable, Sendable {
    let photoIdentifier: String
    let kind: PhotoDecisionKind
    let decidedAt: Date
    let revisitAt: Date?
    let albumIdentifier: String?

    init(
        photoIdentifier: String,
        kind: PhotoDecisionKind,
        decidedAt: Date,
        revisitAt: Date? = nil,
        albumIdentifier: String? = nil
    ) {
        self.photoIdentifier = photoIdentifier
        self.kind = kind
        self.decidedAt = decidedAt
        self.revisitAt = revisitAt
        self.albumIdentifier = albumIdentifier
    }
}

struct PhotoDecisionPolicy: Sendable {
    private let decisionsByIdentifier: [String: PhotoDecision]

    init(decisions: [PhotoDecision]) {
        decisionsByIdentifier = decisions.reduce(into: [:]) { result, decision in
            guard let existing = result[decision.photoIdentifier] else {
                result[decision.photoIdentifier] = decision
                return
            }
            if decision.decidedAt >= existing.decidedAt {
                result[decision.photoIdentifier] = decision
            }
        }
    }

    func isEligible(
        _ photoIdentifier: String,
        for intent: CleanupIntent,
        at date: Date,
        skippedInCurrentSession: Set<String> = []
    ) -> Bool {
        guard !skippedInCurrentSession.contains(photoIdentifier) else { return false }
        guard let decision = decisionsByIdentifier[photoIdentifier] else { return true }

        switch decision.kind {
        case .permanentKeep:
            return intent == .organize
        case .reviewLater:
            guard let revisitAt = decision.revisitAt else { return true }
            return revisitAt <= date
        case .archived:
            return intent == .deleteCleanup
        }
    }
}

protocol ResourceDataSource: AnyObject {
    func requestData(
        received: @escaping (Data) -> Void,
        completion: @escaping (Error?) -> Void
    ) -> Int32

    func cancel(requestID: Int32)
}

final class ResourceSizeLoader {
    private let source: any ResourceDataSource
    private let lock = NSLock()
    private var byteCount: Int64 = 0
    private var requestID: Int32?
    private var isFinished = false

    init(source: any ResourceDataSource) {
        self.source = source
    }

    func load(completion: @escaping (Result<Int64, Error>) -> Void) {
        lock.withLock {
            byteCount = 0
            requestID = nil
            isFinished = false
        }

        let nextRequestID = source.requestData(
            received: { [weak self] data in
                self?.receive(data)
            },
            completion: { [weak self] error in
                self?.finish(error: error, completion: completion)
            }
        )

        lock.withLock {
            if !isFinished {
                requestID = nextRequestID
            }
        }
    }

    func cancel() {
        let requestID = lock.withLock { () -> Int32? in
            guard !isFinished else { return nil }
            isFinished = true
            defer { self.requestID = nil }
            return self.requestID
        }
        if let requestID {
            source.cancel(requestID: requestID)
        }
    }

    private func receive(_ data: Data) {
        lock.withLock {
            guard !isFinished else { return }
            byteCount += Int64(data.count)
        }
    }

    private func finish(
        error: Error?,
        completion: @escaping (Result<Int64, Error>) -> Void
    ) {
        let result = lock.withLock { () -> Result<Int64, Error>? in
            guard !isFinished else { return nil }
            isFinished = true
            requestID = nil
            if let error {
                return .failure(error)
            }
            return .success(byteCount)
        }
        if let result {
            completion(result)
        }
    }
}

@Model
final class PhotoDecisionEntity {
    @Attribute(.unique) var photoIdentifier: String
    var kindRawValue: String
    var decidedAt: Date
    var revisitAt: Date?
    var albumIdentifier: String?

    init(decision: PhotoDecision) {
        photoIdentifier = decision.photoIdentifier
        kindRawValue = decision.kind.rawValue
        decidedAt = decision.decidedAt
        revisitAt = decision.revisitAt
        albumIdentifier = decision.albumIdentifier
    }

    var decision: PhotoDecision? {
        guard let kind = PhotoDecisionKind(rawValue: kindRawValue) else { return nil }
        return PhotoDecision(
            photoIdentifier: photoIdentifier,
            kind: kind,
            decidedAt: decidedAt,
            revisitAt: revisitAt,
            albumIdentifier: albumIdentifier
        )
    }
}

@MainActor
final class PhotoDecisionStore {
    static let shared: PhotoDecisionStore = {
        PhotoDecisionStore(container: PhotoSortDataContainer.shared)
    }()

    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func decisions() throws -> [PhotoDecision] {
        try context.fetch(FetchDescriptor<PhotoDecisionEntity>())
            .compactMap(\.decision)
            .sorted { $0.decidedAt < $1.decidedAt }
    }

    var count: Int {
        (try? context.fetchCount(FetchDescriptor<PhotoDecisionEntity>())) ?? 0
    }

    func set(_ decision: PhotoDecision) throws {
        let entities = try context.fetch(FetchDescriptor<PhotoDecisionEntity>())
        entities
            .filter { $0.photoIdentifier == decision.photoIdentifier }
            .forEach(context.delete)
        context.insert(PhotoDecisionEntity(decision: decision))
        try context.save()
    }

    func removeDecision(for photoIdentifier: String) throws {
        let entities = try context.fetch(FetchDescriptor<PhotoDecisionEntity>())
        entities
            .filter { $0.photoIdentifier == photoIdentifier }
            .forEach(context.delete)
        try context.save()
    }

    func reset() throws {
        try context.delete(model: PhotoDecisionEntity.self)
        try context.save()
    }
}

struct CachedAnalysisRecord: Equatable, Sendable {
    let identifier: String
    let modificationDate: Date?
    let analyzerVersion: Int
    let payload: Data
}

@Model
final class SmartAnalysisRecordEntity {
    @Attribute(.unique) var identifier: String
    var modificationDate: Date?
    var analyzerVersion: Int
    var payload: Data

    init(record: CachedAnalysisRecord) {
        identifier = record.identifier
        modificationDate = record.modificationDate
        analyzerVersion = record.analyzerVersion
        payload = record.payload
    }

    var record: CachedAnalysisRecord {
        CachedAnalysisRecord(
            identifier: identifier,
            modificationDate: modificationDate,
            analyzerVersion: analyzerVersion,
            payload: payload
        )
    }
}

@Model
final class SmartAnalysisMetadataEntity {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }
}

@MainActor
final class SmartAnalysisRecordStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
    }

    func records() throws -> [CachedAnalysisRecord] {
        try context.fetch(FetchDescriptor<SmartAnalysisRecordEntity>())
            .map(\.record)
            .sorted { $0.identifier < $1.identifier }
    }

    func apply(upserts: [CachedAnalysisRecord], deleting identifiers: Set<String>) throws {
        let existing = try context.fetch(FetchDescriptor<SmartAnalysisRecordEntity>())
        let replacedIdentifiers = identifiers.union(upserts.map(\.identifier))
        existing
            .filter { replacedIdentifiers.contains($0.identifier) }
            .forEach(context.delete)
        upserts.forEach { context.insert(SmartAnalysisRecordEntity(record: $0)) }
        try context.save()
    }

    func metadata(for key: String) throws -> Data? {
        try context.fetch(FetchDescriptor<SmartAnalysisMetadataEntity>())
            .first { $0.key == key }?
            .payload
    }

    func setMetadata(_ payload: Data, for key: String) throws {
        let existing = try context.fetch(FetchDescriptor<SmartAnalysisMetadataEntity>())
        existing.filter { $0.key == key }.forEach(context.delete)
        context.insert(SmartAnalysisMetadataEntity(key: key, payload: payload))
        try context.save()
    }

    func reset() throws {
        try context.delete(model: SmartAnalysisRecordEntity.self)
        try context.delete(model: SmartAnalysisMetadataEntity.self)
        try context.save()
    }
}
