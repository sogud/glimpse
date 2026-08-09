import XCTest
@testable import PhotoSortSmartCore

final class PhotoDecisionPolicyTests: XCTestCase {
    func testDecisionKindsAffectOnlyTheirIntendedCleanupContext() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let decisions = [
            PhotoDecision(photoIdentifier: "keep", kind: .permanentKeep, decidedAt: now),
            PhotoDecision(
                photoIdentifier: "later",
                kind: .reviewLater,
                decidedAt: now,
                revisitAt: now.addingTimeInterval(30 * 24 * 60 * 60)
            ),
            PhotoDecision(
                photoIdentifier: "archived",
                kind: .archived,
                decidedAt: now,
                albumIdentifier: "album"
            )
        ]
        let policy = PhotoDecisionPolicy(decisions: decisions)

        XCTAssertFalse(policy.isEligible("keep", for: .deleteCleanup, at: now))
        XCTAssertTrue(policy.isEligible("keep", for: .organize, at: now))
        XCTAssertFalse(policy.isEligible("later", for: .deleteCleanup, at: now))
        XCTAssertTrue(
            policy.isEligible(
                "later",
                for: .deleteCleanup,
                at: now.addingTimeInterval(31 * 24 * 60 * 60)
            )
        )
        XCTAssertTrue(policy.isEligible("archived", for: .deleteCleanup, at: now))
        XCTAssertFalse(policy.isEligible("archived", for: .organize, at: now))
        XCTAssertFalse(
            policy.isEligible(
                "session-skip",
                for: .deleteCleanup,
                at: now,
                skippedInCurrentSession: ["session-skip"]
            )
        )
    }
}
