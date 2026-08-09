import XCTest
@testable import PhotoSortSessionCore

final class CleanupSessionResumePlannerTests: XCTestCase {
    func testResumeSelectsNextUnprocessedSmartCandidate() {
        let state = CleanupSessionState(
            workflow: .delete,
            preset: .smartGroup,
            selectedSourceAlbum: "相似照片",
            selectedTargetAlbum: nil,
            initialCount: 2,
            markedDeleteCount: 0,
            keptCount: 1,
            movedCount: 0,
            estimatedDeletedBytes: 0,
            pendingDeleteIdentifiers: [],
            smartSessionIdentifiers: ["processed", "next"],
            hasCommittedPendingDeletes: false
        )

        let plan = CleanupSessionResumePlanner.makePlan(
            state: state,
            accessibleIdentifiers: ["processed", "next"],
            processedIdentifiers: ["processed"]
        )

        XCTAssertEqual(plan.remainingIdentifiers, ["next"])
        XCTAssertEqual(plan.currentIdentifier, "next")
    }

    func testRepositoryRoundTripPreservesPendingDeletesAndSmartCandidates() throws {
        let suiteName = "CleanupSessionResumePlannerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsCleanupSessionRepository(userDefaults: defaults)
        let state = CleanupSessionState(
            workflow: .delete,
            preset: .smartGroup,
            selectedSourceAlbum: "大视频",
            selectedTargetAlbum: nil,
            initialCount: 3,
            markedDeleteCount: 1,
            keptCount: 1,
            movedCount: 0,
            estimatedDeletedBytes: 2048,
            pendingDeleteIdentifiers: ["pending"],
            smartSessionIdentifiers: ["pending", "kept", "next"],
            hasCommittedPendingDeletes: false,
            processedIdentifiers: ["pending", "kept"]
        )

        try repository.save(state)

        XCTAssertEqual(try repository.load(), state)
    }

    func testResumeDropsUnavailableAssetsAndDoesNotResurfacePendingDeletes() {
        let state = CleanupSessionState(
            workflow: .delete,
            preset: .smartGroup,
            selectedSourceAlbum: "大文件",
            selectedTargetAlbum: nil,
            initialCount: 3,
            markedDeleteCount: 2,
            keptCount: 0,
            movedCount: 0,
            estimatedDeletedBytes: 4096,
            pendingDeleteIdentifiers: ["missing", "pending"],
            smartSessionIdentifiers: ["missing", "pending", "next"],
            hasCommittedPendingDeletes: false
        )

        let plan = CleanupSessionResumePlanner.makePlan(
            state: state,
            accessibleIdentifiers: ["pending", "next"],
            processedIdentifiers: []
        )

        XCTAssertEqual(plan.state.pendingDeleteIdentifiers, ["pending"])
        XCTAssertEqual(plan.state.smartSessionIdentifiers, ["pending", "next"])
        XCTAssertEqual(plan.state.estimatedDeletedBytes, 0)
        XCTAssertEqual(plan.remainingIdentifiers, ["next"])
    }

    func testLimitedAccessPreservesTemporarilyUnavailableIdentifiers() {
        let state = CleanupSessionState(
            workflow: .delete,
            preset: .smartGroup,
            selectedSourceAlbum: "相似照片",
            selectedTargetAlbum: nil,
            initialCount: 2,
            markedDeleteCount: 1,
            keptCount: 0,
            movedCount: 0,
            estimatedDeletedBytes: 1024,
            pendingDeleteIdentifiers: ["hidden"],
            smartSessionIdentifiers: ["hidden", "visible"],
            hasCommittedPendingDeletes: false
        )

        let plan = CleanupSessionResumePlanner.makePlan(
            state: state,
            accessibleIdentifiers: ["visible"],
            processedIdentifiers: [],
            unavailableAssetPolicy: .preserve
        )

        XCTAssertEqual(plan.state.pendingDeleteIdentifiers, ["hidden"])
        XCTAssertEqual(plan.state.smartSessionIdentifiers, ["hidden", "visible"])
        XCTAssertEqual(plan.remainingIdentifiers, ["visible"])
    }

    func testResumeWithoutStoredSessionHasNoSideEffects() throws {
        let suiteName = "CleanupSessionResumePlannerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsCleanupSessionRepository(userDefaults: defaults)
        let restorer = CleanupSessionRestorer(repository: repository)

        let plan = try restorer.resume(
            accessibleIdentifiers: ["photo"],
            processedIdentifiers: []
        )

        XCTAssertNil(plan)
        XCTAssertNil(try repository.load())
    }

    func testPendingDeletesBlockReplacingSession() {
        let state = CleanupSessionState(
            workflow: .delete,
            preset: .screenshots,
            selectedSourceAlbum: nil,
            selectedTargetAlbum: nil,
            initialCount: 2,
            markedDeleteCount: 1,
            keptCount: 0,
            movedCount: 0,
            estimatedDeletedBytes: 1024,
            pendingDeleteIdentifiers: ["pending"],
            smartSessionIdentifiers: [],
            hasCommittedPendingDeletes: false
        )

        XCTAssertFalse(CleanupSessionReplacementPolicy.canReplace(state))
    }

    func testPartialDeleteCommitKeepsUncommittedIdentifiers() {
        let state = CleanupSessionState(
            workflow: .delete,
            preset: .smartGroup,
            selectedSourceAlbum: "大视频",
            selectedTargetAlbum: nil,
            initialCount: 2,
            markedDeleteCount: 2,
            keptCount: 0,
            movedCount: 0,
            estimatedDeletedBytes: 4096,
            pendingDeleteIdentifiers: ["visible", "hidden"],
            smartSessionIdentifiers: ["visible", "hidden"],
            hasCommittedPendingDeletes: false
        )

        let reconciled = CleanupDeleteCommitPolicy.reconcile(
            state: state,
            committedIdentifiers: ["visible"]
        )

        XCTAssertEqual(reconciled.pendingDeleteIdentifiers, ["hidden"])
        XCTAssertFalse(reconciled.hasCommittedPendingDeletes)
        XCTAssertEqual(reconciled.estimatedDeletedBytes, 0)
    }

}
