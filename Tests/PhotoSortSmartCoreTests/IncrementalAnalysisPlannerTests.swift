import XCTest
@testable import PhotoSortSmartCore

final class IncrementalAnalysisPlannerTests: XCTestCase {
    func testPlansOnlyAddedUpdatedAndDeletedAssets() {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedDate = originalDate.addingTimeInterval(60)
        let cached = [
            AssetFingerprint(id: "unchanged", modificationDate: originalDate, analyzerVersion: 1),
            AssetFingerprint(id: "updated", modificationDate: originalDate, analyzerVersion: 1),
            AssetFingerprint(id: "deleted", modificationDate: originalDate, analyzerVersion: 1)
        ]
        let current = [
            AssetFingerprint(id: "unchanged", modificationDate: originalDate, analyzerVersion: 1),
            AssetFingerprint(id: "updated", modificationDate: updatedDate, analyzerVersion: 1),
            AssetFingerprint(id: "added", modificationDate: originalDate, analyzerVersion: 1)
        ]

        let plan = IncrementalAnalysisPlanner.plan(cached: cached, current: current)

        XCTAssertEqual(plan.addedIdentifiers, ["added"])
        XCTAssertEqual(plan.updatedIdentifiers, ["updated"])
        XCTAssertEqual(plan.deletedIdentifiers, ["deleted"])
        XCTAssertEqual(plan.unchangedIdentifiers, ["unchanged"])
        XCTAssertEqual(plan.identifiersRequiringAnalysis, ["added", "updated"])
    }
}
