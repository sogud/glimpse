import Foundation
import SwiftData
import XCTest
@testable import PhotoSortSmartCore

final class SmartAnalysisRecordStoreTests: XCTestCase {
    @MainActor
    func testAppliesIncrementalUpsertsAndDeletesWithoutLosingUnchangedRecords() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SmartAnalysisRecordEntity.self,
            SmartAnalysisMetadataEntity.self,
            configurations: configuration
        )
        let store = SmartAnalysisRecordStore(container: container)
        let originalDate = Date(timeIntervalSince1970: 100)

        try store.apply(
            upserts: [
                CachedAnalysisRecord(identifier: "a", modificationDate: originalDate, analyzerVersion: 1, payload: Data("a1".utf8)),
                CachedAnalysisRecord(identifier: "b", modificationDate: originalDate, analyzerVersion: 1, payload: Data("b1".utf8))
            ],
            deleting: []
        )

        try store.apply(
            upserts: [
                CachedAnalysisRecord(identifier: "a", modificationDate: originalDate.addingTimeInterval(10), analyzerVersion: 1, payload: Data("a2".utf8)),
                CachedAnalysisRecord(identifier: "c", modificationDate: nil, analyzerVersion: 1, payload: Data("c1".utf8))
            ],
            deleting: ["b"]
        )

        let records = try store.records()
        XCTAssertEqual(Set(records.map(\.identifier)), ["a", "c"])
        XCTAssertEqual(records.first(where: { $0.identifier == "a" })?.payload, Data("a2".utf8))

        try store.setMetadata(Data("snapshot".utf8), for: "latest")
        XCTAssertEqual(try store.metadata(for: "latest"), Data("snapshot".utf8))
    }
}
