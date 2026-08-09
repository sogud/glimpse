import Foundation
import SwiftData

/// 智能分析缓存按照片独立持久化，扫描时只更新发生变化的记录。
@MainActor
final class SmartPhotoAnalysisStore {
    static let shared: SmartPhotoAnalysisStore = {
        SmartPhotoAnalysisStore(
            recordStore: SmartAnalysisRecordStore(container: PhotoSortDataContainer.shared)
        )
    }()

    private let recordStore: SmartAnalysisRecordStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let metadataKey = "latest-snapshot"

    init(recordStore: SmartAnalysisRecordStore) {
        self.recordStore = recordStore
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSnapshot() throws -> SmartAnalysisSnapshot? {
        guard let metadataData = try recordStore.metadata(for: metadataKey) else { return nil }
        let metadata = try decoder.decode(SmartAnalysisSnapshotMetadata.self, from: metadataData)
        let records = try recordStore.records().reduce(into: [String: SmartAssetAnalysisRecord]()) { result, cached in
            guard let record = try? decoder.decode(SmartAssetAnalysisRecord.self, from: cached.payload) else { return }
            result[cached.identifier] = record
        }
        return SmartAnalysisSnapshot(
            analyzerVersion: metadata.analyzerVersion,
            visionAnalyzerVersion: metadata.visionAnalyzerVersion,
            scannedAt: metadata.scannedAt,
            totalAssetCount: metadata.totalAssetCount,
            recordsByIdentifier: records,
            groups: metadata.groups
        )
    }

    func saveSnapshot(_ snapshot: SmartAnalysisSnapshot) throws {
        let existing = try recordStore.records()
        let existingByIdentifier = Dictionary(uniqueKeysWithValues: existing.map { ($0.identifier, $0) })
        let currentIdentifiers = Set(snapshot.recordsByIdentifier.keys)
        let deletedIdentifiers = Set(existingByIdentifier.keys).subtracting(currentIdentifiers)
        let upserts = try snapshot.recordsByIdentifier.values.compactMap { record -> CachedAnalysisRecord? in
            let payload = try encoder.encode(record)
            if existingByIdentifier[record.localIdentifier]?.payload == payload { return nil }
            return CachedAnalysisRecord(
                identifier: record.localIdentifier,
                modificationDate: record.modificationDate,
                analyzerVersion: record.analyzerVersion,
                payload: payload
            )
        }
        try recordStore.apply(upserts: upserts, deleting: deletedIdentifiers)

        let metadata = SmartAnalysisSnapshotMetadata(snapshot: snapshot)
        try recordStore.setMetadata(try encoder.encode(metadata), for: metadataKey)
    }

    func reset() throws {
        try recordStore.reset()
    }
}

private struct SmartAnalysisSnapshotMetadata: Codable {
    let analyzerVersion: Int
    let visionAnalyzerVersion: Int
    let scannedAt: Date
    let totalAssetCount: Int
    let groups: [SmartInsightGroup]

    init(snapshot: SmartAnalysisSnapshot) {
        analyzerVersion = snapshot.analyzerVersion
        visionAnalyzerVersion = snapshot.visionAnalyzerVersion
        scannedAt = snapshot.scannedAt
        totalAssetCount = snapshot.totalAssetCount
        groups = snapshot.groups
    }
}
