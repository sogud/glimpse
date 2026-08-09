import Foundation

/// 可持久化的一次清理会话状态。
struct CleanupSessionState: Codable, Equatable {
    let workflow: CleanupWorkflow
    let preset: CleanupPreset
    let selectedSourceAlbum: String?
    let selectedTargetAlbum: String?
    let initialCount: Int
    let markedDeleteCount: Int
    let keptCount: Int
    let movedCount: Int
    let estimatedDeletedBytes: Int64
    let pendingDeleteIdentifiers: [String]
    let smartSessionIdentifiers: [String]
    let hasCommittedPendingDeletes: Bool
    let processedIdentifiers: [String]

    init(
        workflow: CleanupWorkflow,
        preset: CleanupPreset,
        selectedSourceAlbum: String?,
        selectedTargetAlbum: String?,
        initialCount: Int,
        markedDeleteCount: Int,
        keptCount: Int,
        movedCount: Int,
        estimatedDeletedBytes: Int64,
        pendingDeleteIdentifiers: [String],
        smartSessionIdentifiers: [String],
        hasCommittedPendingDeletes: Bool,
        processedIdentifiers: [String] = []
    ) {
        self.workflow = workflow
        self.preset = preset
        self.selectedSourceAlbum = selectedSourceAlbum
        self.selectedTargetAlbum = selectedTargetAlbum
        self.initialCount = initialCount
        self.markedDeleteCount = markedDeleteCount
        self.keptCount = keptCount
        self.movedCount = movedCount
        self.estimatedDeletedBytes = estimatedDeletedBytes
        self.pendingDeleteIdentifiers = pendingDeleteIdentifiers
        self.smartSessionIdentifiers = smartSessionIdentifiers
        self.hasCommittedPendingDeletes = hasCommittedPendingDeletes
        self.processedIdentifiers = processedIdentifiers
    }
}

/// 防止新会话覆盖尚未提交的待删除清单。
enum CleanupSessionReplacementPolicy {
    static func canReplace(_ state: CleanupSessionState?) -> Bool {
        guard let state else { return true }
        return state.pendingDeleteIdentifiers.isEmpty || state.hasCommittedPendingDeletes
    }
}

/// 只从待删除清单中移除系统已经确认提交的资源。
enum CleanupDeleteCommitPolicy {
    static func reconcile(
        state: CleanupSessionState,
        committedIdentifiers: Set<String>
    ) -> CleanupSessionState {
        let remainingPendingIdentifiers = state.pendingDeleteIdentifiers.filter {
            !committedIdentifiers.contains($0)
        }

        return CleanupSessionState(
            workflow: state.workflow,
            preset: state.preset,
            selectedSourceAlbum: state.selectedSourceAlbum,
            selectedTargetAlbum: state.selectedTargetAlbum,
            initialCount: state.initialCount,
            markedDeleteCount: state.markedDeleteCount,
            keptCount: state.keptCount,
            movedCount: state.movedCount,
            estimatedDeletedBytes: 0,
            pendingDeleteIdentifiers: remainingPendingIdentifiers,
            smartSessionIdentifiers: state.smartSessionIdentifiers,
            hasCommittedPendingDeletes: remainingPendingIdentifiers.isEmpty,
            processedIdentifiers: state.processedIdentifiers
        )
    }
}

/// 清理会话持久化接口，调用方无需了解底层存储键。
protocol CleanupSessionRepository {
    func load() throws -> CleanupSessionState?
    func save(_ state: CleanupSessionState) throws
    func clear()
}

/// 使用单一编码对象持久化会话，避免多个键之间出现不一致。
final class UserDefaultsCleanupSessionRepository: CleanupSessionRepository {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "cleanup_session_state_v2"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() throws -> CleanupSessionState? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try JSONDecoder().decode(CleanupSessionState.self, from: data)
    }

    func save(_ state: CleanupSessionState) throws {
        userDefaults.set(try JSONEncoder().encode(state), forKey: storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }
}

/// 恢复会话后可供界面继续处理的候选。
struct CleanupSessionResumePlan: Equatable {
    let state: CleanupSessionState
    let remainingIdentifiers: [String]

    var currentIdentifier: String? {
        remainingIdentifiers.first
    }
}

/// 当前不可见资源在完整权限与有限权限下需要不同处理。
enum UnavailableAssetPolicy {
    case discard
    case preserve
}

/// 将持久化状态与当前照片库状态合并为可继续执行的计划。
enum CleanupSessionResumePlanner {
    static func makePlan(
        state: CleanupSessionState,
        accessibleIdentifiers: [String],
        processedIdentifiers: Set<String>,
        unavailableAssetPolicy: UnavailableAssetPolicy = .discard
    ) -> CleanupSessionResumePlan {
        let accessible = Set(accessibleIdentifiers)
        let accessiblePendingDeleteIdentifiers = state.pendingDeleteIdentifiers.filter(accessible.contains)
        let accessibleSmartSessionIdentifiers = state.smartSessionIdentifiers.filter(accessible.contains)
        let pendingDeleteIdentifiers = unavailableAssetPolicy == .preserve
            ? state.pendingDeleteIdentifiers
            : accessiblePendingDeleteIdentifiers
        let smartSessionIdentifiers = unavailableAssetPolicy == .preserve
            ? state.smartSessionIdentifiers
            : accessibleSmartSessionIdentifiers
        let removedPendingIdentifiers = pendingDeleteIdentifiers.count != state.pendingDeleteIdentifiers.count
        let pendingDeletes = Set(pendingDeleteIdentifiers)
        let candidateOrder = state.preset == .smartGroup
            ? accessibleSmartSessionIdentifiers
            : accessibleIdentifiers
        let allProcessedIdentifiers = processedIdentifiers.union(state.processedIdentifiers)
        let remainingIdentifiers = candidateOrder.filter {
            !allProcessedIdentifiers.contains($0) && !pendingDeletes.contains($0)
        }

        let restoredState = CleanupSessionState(
            workflow: state.workflow,
            preset: state.preset,
            selectedSourceAlbum: state.selectedSourceAlbum,
            selectedTargetAlbum: state.selectedTargetAlbum,
            initialCount: state.initialCount,
            markedDeleteCount: state.markedDeleteCount,
            keptCount: state.keptCount,
            movedCount: state.movedCount,
            estimatedDeletedBytes: removedPendingIdentifiers ? 0 : state.estimatedDeletedBytes,
            pendingDeleteIdentifiers: pendingDeleteIdentifiers,
            smartSessionIdentifiers: smartSessionIdentifiers,
            hasCommittedPendingDeletes: state.hasCommittedPendingDeletes,
            processedIdentifiers: state.processedIdentifiers
        )

        return CleanupSessionResumePlan(
            state: restoredState,
            remainingIdentifiers: remainingIdentifiers
        )
    }
}

/// 通过会话仓库恢复状态，并写回清理后的有效资源列表。
final class CleanupSessionRestorer {
    private let repository: any CleanupSessionRepository

    init(repository: any CleanupSessionRepository) {
        self.repository = repository
    }

    func resume(
        accessibleIdentifiers: [String],
        processedIdentifiers: Set<String>,
        unavailableAssetPolicy: UnavailableAssetPolicy = .discard
    ) throws -> CleanupSessionResumePlan? {
        guard let state = try repository.load() else { return nil }

        let plan = CleanupSessionResumePlanner.makePlan(
            state: state,
            accessibleIdentifiers: accessibleIdentifiers,
            processedIdentifiers: processedIdentifiers,
            unavailableAssetPolicy: unavailableAssetPolicy
        )
        try repository.save(plan.state)
        return plan
    }
}
