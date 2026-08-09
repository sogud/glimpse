import SwiftData
import XCTest
@testable import PhotoSortSmartCore

final class PhotoDecisionStoreTests: XCTestCase {
    @MainActor
    func testPersistsAndReloadsPhotoDecision() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PhotoDecisionEntity.self,
            configurations: configuration
        )
        let store = PhotoDecisionStore(container: container)
        let decidedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let revisitAt = decidedAt.addingTimeInterval(30 * 24 * 60 * 60)
        let decision = PhotoDecision(
            photoIdentifier: "photo",
            kind: .reviewLater,
            decidedAt: decidedAt,
            revisitAt: revisitAt
        )

        try store.set(decision)

        XCTAssertEqual(try store.decisions(), [decision])
    }
}
