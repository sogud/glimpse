import Photos
import SwiftUI

/// 主要的视图模型，协调删图会话、归档会话、PhotoKit 和界面状态。
@MainActor
class PhotoSwipeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var currentIndex = 0
    @Published var currentPhoto: PhotoAsset?
    @Published var allPhotos: [PhotoAsset] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var authorizationStatus: PhotoLibraryService.AuthorizationStatus = .notDetermined
    @Published var selectedSourceAlbum: String?
    @Published private(set) var isPerformingAction = false
    @Published private(set) var canUndo = false
    @Published private(set) var activeWorkflow: CleanupWorkflow?
    @Published private(set) var activePreset: CleanupPreset?
    @Published private(set) var selectedTargetAlbum: String?
    @Published private(set) var sessionInitialCount = 0
    @Published private(set) var pendingDeleteCount = 0
    @Published private(set) var markedDeleteCount = 0
    @Published private(set) var keptCount = 0
    @Published private(set) var movedCount = 0
    @Published private(set) var estimatedDeletedBytes: Int64 = 0
    @Published private(set) var hasCommittedPendingDeletes = false

    // MARK: - Private Properties

    private let service: PhotoLibraryService
    private let sessionRepository: any CleanupSessionRepository
    private let sessionRestorer: CleanupSessionRestorer
    private let decisionStore: PhotoDecisionStore
    private var pendingDeleteIdentifiers: [String] = []
    private var smartSessionIdentifiers: [String] = []
    private var sessionProcessedIdentifiers = Set<String>()
    private var resumeCandidateIdentifiers: [String]?
    private var hasAttemptedSessionLoad = false
    private var isResumingSession = false

    // 增量加载相关属性
    private var loadedPhotoCount = 0
    private var fetchedPhotoCount = 0
    private var isLoadingMore = false
    private let loadBatchSize = 50
    private let loadMoreThreshold = 5
    private var hasLoadedAllPhotos = false

    private enum UndoAction {
        case permanentKeep
        case skip
        case reviewLater
        case move(albumName: String)
        case markDelete(estimatedBytes: Int64)
    }

    private struct UndoEntry {
        let action: UndoAction
        let assetIdentifier: String
        let index: Int
    }

    private var undoStack: [UndoEntry] = []

    // MARK: - Initialization

    init(
        service: PhotoLibraryService = PhotoLibraryService(),
        sessionRepository: any CleanupSessionRepository = UserDefaultsCleanupSessionRepository(),
        decisionStore: PhotoDecisionStore? = nil
    ) {
        self.service = service
        self.sessionRepository = sessionRepository
        self.sessionRestorer = CleanupSessionRestorer(repository: sessionRepository)
        self.decisionStore = decisionStore ?? .shared
        restoreSessionState()
        checkAuthorizationStatus()
    }

    // MARK: - Computed Properties

    var hasActiveSession: Bool {
        activePreset != nil && activeWorkflow != nil
    }

    var savedDecisionCount: Int {
        decisionStore.count
    }

    var isSessionComplete: Bool {
        hasActiveSession && hasAttemptedSessionLoad && !isLoading && allPhotos.isEmpty
    }

    var hasPendingDeletionReview: Bool {
        activeWorkflow == .delete && pendingDeleteCount > 0
    }

    var currentSessionTitle: String {
        sessionSummary?.title ?? "本次处理"
    }

    var currentSessionSubtitle: String {
        guard let summary = sessionSummary else {
            return "删除会进入系统“最近删除”，仍可在系统相册中恢复。"
        }

        switch summary.workflow {
        case .delete:
            if hasCommittedPendingDeletes {
                return "已提交系统删除 · 共 \(summary.processedCount) 张"
            }
            if summary.processedCount == 0 {
                if let targetAlbum = summary.targetAlbumName, !targetAlbum.isEmpty {
                    return "左滑待删除，右滑可归档到 \(targetAlbum)"
                }
                return "左滑待删除，右滑保留"
            }
            return "已标记删除 \(summary.markedDeleteCount) 张"
        case .organize:
            if summary.processedCount == 0 {
                if let targetAlbum = summary.targetAlbumName, !targetAlbum.isEmpty {
                    return "右滑加入 \(targetAlbum)，左滑跳过"
                }
                return "右滑加入相册，左滑跳过"
            }
            if let targetAlbum = summary.targetAlbumName, !targetAlbum.isEmpty {
                return "归档到 \(targetAlbum) · 已处理 \(summary.processedCount) 张"
            }
            return "归档到相册 · 已处理 \(summary.processedCount) 张"
        }
    }

    var currentSessionChipSubtitle: String {
        guard let summary = sessionSummary else {
            return ""
        }

        switch summary.workflow {
        case .delete:
            if hasCommittedPendingDeletes {
                return "已提交"
            }
            if pendingDeleteCount > 0 {
                return "待删 \(pendingDeleteCount)"
            }
            if summary.processedCount == 0 {
                return currentArchiveAlbumName == nil ? "左删右留" : "左删右归档"
            }
            return "待删 \(summary.markedDeleteCount)"
        case .organize:
            if summary.processedCount == 0 {
                return "右滑归档"
            }
            return "已处理 \(summary.processedCount)"
        }
    }

    private var currentArchiveAlbumName: String? {
        selectedTargetAlbum?.trimmedNilIfEmpty
    }

    var sessionSummary: CleanupSessionSummary? {
        guard let activeWorkflow, let activePreset else { return nil }
        return CleanupSessionSummary(
            workflow: activeWorkflow,
            preset: activePreset,
            sourceAlbumName: selectedSourceAlbum,
            targetAlbumName: selectedTargetAlbum,
            initialCount: sessionInitialCount,
            markedDeleteCount: markedDeleteCount,
            keptCount: keptCount,
            movedCount: movedCount,
            estimatedDeletedBytes: estimatedDeletedBytes,
            hasCommittedPendingDeletes: hasCommittedPendingDeletes
        )
    }

    // MARK: - Public Methods

    func requestPermission() async {
        isLoading = true
        defer { isLoading = false }

        let status = await service.requestAuthorization()
        authorizationStatus = status

        guard status == .authorized || status == .limited else { return }
        await resumeCurrentSessionIfNeeded()
    }

    func startSession(
        workflow: CleanupWorkflow,
        preset: CleanupPreset,
        sourceAlbum: String? = nil,
        targetAlbum: String? = nil
    ) async {
        guard canReplaceCurrentSession() else { return }

        activeWorkflow = workflow
        activePreset = preset
        selectedSourceAlbum = preset == .advancedAlbum ? sourceAlbum : nil
        selectedTargetAlbum = targetAlbum?.trimmedNilIfEmpty
        smartSessionIdentifiers = []
        sessionProcessedIdentifiers.removeAll()
        resumeCandidateIdentifiers = nil
        sessionInitialCount = 0
        pendingDeleteCount = 0
        markedDeleteCount = 0
        keptCount = 0
        movedCount = 0
        estimatedDeletedBytes = 0
        hasCommittedPendingDeletes = false
        hasAttemptedSessionLoad = false
        pendingDeleteIdentifiers.removeAll()
        undoStack.removeAll()
        canUndo = false
        // 重置增量加载状态
        loadedPhotoCount = 0
        fetchedPhotoCount = 0
        isLoadingMore = false
        hasLoadedAllPhotos = false
        persistSessionState()

        do {
            try await loadPhotos(resetSessionCount: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startSmartReviewSession(title: String, localIdentifiers: [String]) async {
        guard canReplaceCurrentSession() else { return }

        let uniqueIdentifiers = localIdentifiers.reduce(into: [String]()) { result, identifier in
            guard !result.contains(identifier) else { return }
            result.append(identifier)
        }
        guard !uniqueIdentifiers.isEmpty else {
            errorMessage = "这个分组里没有可复核的照片。"
            return
        }

        activeWorkflow = .delete
        activePreset = .smartGroup
        selectedSourceAlbum = title.trimmedNilIfEmpty ?? "智能分组"
        selectedTargetAlbum = nil
        smartSessionIdentifiers = uniqueIdentifiers
        sessionProcessedIdentifiers.removeAll()
        resumeCandidateIdentifiers = nil
        sessionInitialCount = 0
        pendingDeleteCount = 0
        markedDeleteCount = 0
        keptCount = 0
        movedCount = 0
        estimatedDeletedBytes = 0
        hasCommittedPendingDeletes = false
        hasAttemptedSessionLoad = false
        pendingDeleteIdentifiers.removeAll()
        undoStack.removeAll()
        canUndo = false
        loadedPhotoCount = 0
        fetchedPhotoCount = 0
        isLoadingMore = false
        hasLoadedAllPhotos = false
        persistSessionState()

        do {
            try await loadPhotos(resetSessionCount: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPhotos(resetSessionCount: Bool = false) async throws {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryService.PhotoLibraryError.insufficientPermission
        }
        guard let activePreset else {
            allPhotos = []
            currentPhoto = nil
            currentIndex = 0
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 重置增量加载状态
            fetchedPhotoCount = 0
            loadedPhotoCount = 0
            isLoadingMore = false
            hasLoadedAllPhotos = false
            allPhotos = []
            currentIndex = 0
            currentPhoto = nil

            // 如果是重置会话，获取总候选数量
            if resetSessionCount {
                let totalAssets: [PHAsset]
                if activePreset == .smartGroup {
                    totalAssets = try service.fetchPhotosPage(
                        withLocalIdentifiers: smartSessionIdentifiers,
                        limit: smartSessionIdentifiers.count,
                        offset: 0
                    ).assets
                } else {
                    let excludeAlbums = effectiveExcludedAlbums()
                    totalAssets = try service.fetchPhotos(
                        preset: activePreset,
                        sourceAlbum: selectedSourceAlbum,
                        limit: 2000,
                        offset: 0,
                        excludeAlbums: excludeAlbums
                    )
                }
                let policy = try decisionPolicy()
                let totalFiltered = totalAssets.filter {
                    policy.isEligible(
                        $0.localIdentifier,
                        for: cleanupIntent,
                        at: Date(),
                        skippedInCurrentSession: sessionProcessedIdentifiers
                    )
                }
                sessionInitialCount = totalFiltered.count
            }

            try await loadMorePhotos()
            hasAttemptedSessionLoad = true
            persistSessionState()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func performSwipe(_ direction: GestureDirection, archiveAlbum: String?) async {
        guard currentPhoto != nil, !isPerformingAction else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        switch activeWorkflow {
        case .delete:
            switch direction {
            case .left:
                markCurrentPhotoForDeletion()
            case .right:
                if let archiveAlbum = archiveAlbum?.trimmedNilIfEmpty {
                    await moveCurrentPhotoToAlbum(archiveAlbum)
                } else {
                    keepCurrentPhoto()
                }
            default:
                break
            }
        case .organize:
            switch direction {
            case .left:
                keepCurrentPhoto()
            case .right:
                guard let targetAlbum = selectedTargetAlbum?.trimmedNilIfEmpty else {
                    errorMessage = "请先选择一个归档相册。"
                    return
                }
                await moveCurrentPhotoToAlbum(targetAlbum)
            default:
                break
            }
        case .none:
            break
        }
    }

    func keepCurrentPhoto() {
        guard let currentPhoto else { return }
        let identifier = currentPhoto.asset.localIdentifier
        let action: UndoAction

        if activeWorkflow == .delete {
            do {
                try decisionStore.set(PhotoDecision(
                    photoIdentifier: identifier,
                    kind: .permanentKeep,
                    decidedAt: Date()
                ))
            } catch {
                errorMessage = "无法保存保留决定: \(error.localizedDescription)"
                return
            }
            action = .permanentKeep
        } else {
            action = .skip
        }

        pushUndo(
            action: action,
            assetIdentifier: identifier,
            index: currentIndex
        )
        keptCount += 1
        removeCurrentPhoto()
    }

    func reviewCurrentPhotoLater() {
        guard let currentPhoto, !isPerformingAction else { return }
        let identifier = currentPhoto.asset.localIdentifier
        do {
            try decisionStore.set(PhotoDecision(
                photoIdentifier: identifier,
                kind: .reviewLater,
                decidedAt: Date(),
                revisitAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
            ))
            pushUndo(action: .reviewLater, assetIdentifier: identifier, index: currentIndex)
            keptCount += 1
            removeCurrentPhoto()
        } catch {
            errorMessage = "无法保存稍后处理决定: \(error.localizedDescription)"
        }
    }

    func commitPendingDeletes() async {
        guard hasPendingDeletionReview, !isPerformingAction else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let accessibleAssets = try service.fetchPhotosPage(
                withLocalIdentifiers: pendingDeleteIdentifiers,
                limit: pendingDeleteIdentifiers.count,
                offset: 0
            ).assets
            let accessibleIdentifiers = Set(accessibleAssets.map(\.localIdentifier))
            if authorizationStatus == .limited && accessibleIdentifiers.isEmpty {
                errorMessage = "当前授权范围内没有可删除的照片，请先调整相册权限。"
                return
            }

            let success = try await service.deletePhotos(
                withLocalIdentifiers: Array(accessibleIdentifiers)
            )
            if success {
                let committedIdentifiers = authorizationStatus == .limited
                    ? accessibleIdentifiers
                    : Set(pendingDeleteIdentifiers)
                if let state = currentSessionState() {
                    applySessionState(
                        CleanupDeleteCommitPolicy.reconcile(
                            state: state,
                            committedIdentifiers: committedIdentifiers
                        )
                    )
                    undoStack.removeAll { committedIdentifiers.contains($0.assetIdentifier) }
                    canUndo = !undoStack.isEmpty
                    persistSessionState()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardPendingDeletes() {
        guard !pendingDeleteIdentifiers.isEmpty else { return }

        let pendingCount = pendingDeleteCount
        sessionProcessedIdentifiers.subtract(pendingDeleteIdentifiers)
        resumeCandidateIdentifiers = nil
        pendingDeleteIdentifiers.removeAll()
        pendingDeleteCount = 0
        markedDeleteCount = max(markedDeleteCount - pendingCount, 0)
        estimatedDeletedBytes = 0
        hasCommittedPendingDeletes = false
        undoStack.removeAll()
        canUndo = false
        persistSessionState()

        Task {
            do {
                try await loadPhotos(resetSessionCount: false)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func moveCurrentPhotoToAlbum(_ albumName: String) async {
        guard let currentPhoto else { return }

        do {
            let success = try await service.movePhotoToAlbum(currentPhoto.asset, albumName: albumName)
            if success {
                try decisionStore.set(PhotoDecision(
                    photoIdentifier: currentPhoto.asset.localIdentifier,
                    kind: .archived,
                    decidedAt: Date(),
                    albumIdentifier: albumName
                ))
                pushUndo(
                    action: .move(albumName: albumName),
                    assetIdentifier: currentPhoto.asset.localIdentifier,
                    index: currentIndex
                )
                movedCount += 1
                removeCurrentPhoto()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undoLastAction() {
        guard !isPerformingAction, let lastAction = popUndo() else { return }

        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }

            do {
                switch lastAction.action {
                case .permanentKeep, .reviewLater:
                    keptCount = max(keptCount - 1, 0)
                    sessionProcessedIdentifiers.remove(lastAction.assetIdentifier)
                    resumeCandidateIdentifiers = nil
                    try decisionStore.removeDecision(for: lastAction.assetIdentifier)
                case .skip:
                    keptCount = max(keptCount - 1, 0)
                    sessionProcessedIdentifiers.remove(lastAction.assetIdentifier)
                    resumeCandidateIdentifiers = nil
                case .move(let albumName):
                    movedCount = max(movedCount - 1, 0)
                    _ = try await service.removePhotoFromAlbum(
                        withLocalIdentifier: lastAction.assetIdentifier,
                        albumName: albumName
                    )
                    sessionProcessedIdentifiers.remove(lastAction.assetIdentifier)
                    resumeCandidateIdentifiers = nil
                    try decisionStore.removeDecision(for: lastAction.assetIdentifier)
                case .markDelete(let estimatedBytes):
                    markedDeleteCount = max(markedDeleteCount - 1, 0)
                    estimatedDeletedBytes = max(estimatedDeletedBytes - estimatedBytes, 0)
                    pendingDeleteIdentifiers.removeAll { $0 == lastAction.assetIdentifier }
                    pendingDeleteCount = max(pendingDeleteCount - 1, 0)
                    hasCommittedPendingDeletes = false
                    sessionProcessedIdentifiers.remove(lastAction.assetIdentifier)
                    resumeCandidateIdentifiers = nil
                }

                persistSessionState()
                try await loadPhotos(resetSessionCount: false)
                restorePhotoPosition(with: lastAction.assetIdentifier, fallbackIndex: lastAction.index)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func resetForNewSession() {
        activeWorkflow = nil
        activePreset = nil
        selectedTargetAlbum = nil
        smartSessionIdentifiers = []
        sessionProcessedIdentifiers.removeAll()
        resumeCandidateIdentifiers = nil
        allPhotos = []
        currentPhoto = nil
        currentIndex = 0
        sessionInitialCount = 0
        pendingDeleteCount = 0
        markedDeleteCount = 0
        keptCount = 0
        movedCount = 0
        estimatedDeletedBytes = 0
        hasCommittedPendingDeletes = false
        hasAttemptedSessionLoad = false
        pendingDeleteIdentifiers.removeAll()
        undoStack.removeAll()
        canUndo = false
        // 重置增量加载状态
        loadedPhotoCount = 0
        fetchedPhotoCount = 0
        isLoadingMore = false
        hasLoadedAllPhotos = false
        clearPersistedSessionState()
    }

    func resetAllSavedDecisions() {
        do {
            try decisionStore.reset()
            resetForNewSession()
        } catch {
            errorMessage = "无法重置整理记录: \(error.localizedDescription)"
        }
    }

    func reloadCurrentSession() async {
        guard hasActiveSession else { return }
        hasAttemptedSessionLoad = false
        resumeCandidateIdentifiers = nil
        do {
            try await loadPhotos(resetSessionCount: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkAuthorizationStatus() {
        let nextStatus = service.currentAuthorizationStatus()
        if authorizationStatus != nextStatus, hasActiveSession {
            hasAttemptedSessionLoad = false
            resumeCandidateIdentifiers = nil
        }
        authorizationStatus = nextStatus
    }

    /// 在应用重启或重新获得相册权限后继续未完成的会话。
    func resumeCurrentSessionIfNeeded() async {
        guard hasActiveSession, !hasAttemptedSessionLoad, !isResumingSession else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .limited else { return }

        isResumingSession = true
        defer { isResumingSession = false }

        do {
            try normalizeRestoredSessionState()
            try await loadPhotos(resetSessionCount: false)
        } catch {
            errorMessage = "恢复上次会话失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func effectiveExcludedAlbums() -> [String] {
        guard let target = selectedTargetAlbum?.trimmedNilIfEmpty else { return [] }
        // 当用户明确选择“源相册”时，不应因为归档目标相册而把该相册整本排除掉。
        if activePreset == .advancedAlbum,
           let source = selectedSourceAlbum?.trimmedNilIfEmpty,
           source == target {
            return []
        }
        return [target]
    }

    private func markCurrentPhotoForDeletion() {
        guard let currentPhoto else { return }

        let identifier = currentPhoto.asset.localIdentifier
        let estimatedBytes = currentPhoto.fileSize ?? 0
        pushUndo(
            action: .markDelete(estimatedBytes: estimatedBytes),
            assetIdentifier: identifier,
            index: currentIndex
        )
        pendingDeleteIdentifiers.append(identifier)
        pendingDeleteCount += 1
        markedDeleteCount += 1
        estimatedDeletedBytes += estimatedBytes
        hasCommittedPendingDeletes = false
        removeCurrentPhoto()
    }

    private func canReplaceCurrentSession() -> Bool {
        guard CleanupSessionReplacementPolicy.canReplace(currentSessionState()) else {
            errorMessage = "请先确认删除或清空当前待删除清单，再开始新的清理。"
            return false
        }
        return true
    }

    private func normalizeRestoredSessionState() throws {
        guard let state = currentSessionState() else { return }

        let sessionAssets: [PHAsset]
        if state.preset == .smartGroup {
            sessionAssets = try service.fetchPhotosPage(
                withLocalIdentifiers: state.smartSessionIdentifiers,
                limit: state.smartSessionIdentifiers.count,
                offset: 0
            ).assets
        } else {
            sessionAssets = try service.fetchPhotos(
                preset: state.preset,
                sourceAlbum: state.selectedSourceAlbum,
                limit: 2000,
                offset: 0,
                excludeAlbums: effectiveExcludedAlbums()
            )
        }

        let pendingAssets = try service.fetchPhotosPage(
            withLocalIdentifiers: state.pendingDeleteIdentifiers,
            limit: state.pendingDeleteIdentifiers.count,
            offset: 0
        ).assets
        let accessibleIdentifiers = Array(
            Set((sessionAssets + pendingAssets).map(\.localIdentifier))
        )
        guard let plan = try sessionRestorer.resume(
            accessibleIdentifiers: accessibleIdentifiers,
            processedIdentifiers: [],
            unavailableAssetPolicy: authorizationStatus == .limited ? .preserve : .discard
        ) else { return }
        applySessionState(plan.state)
        if plan.state.preset == .smartGroup {
            resumeCandidateIdentifiers = plan.remainingIdentifiers
        }
    }

    private func removeCurrentPhoto() {
        guard !allPhotos.isEmpty else { return }

        let removedPhoto = allPhotos[currentIndex]
        let removedIdentifier = removedPhoto.asset.localIdentifier
        sessionProcessedIdentifiers.insert(removedIdentifier)
        allPhotos.remove(at: currentIndex)

        if allPhotos.isEmpty {
            currentPhoto = nil
            currentIndex = 0
            // 触发增量加载
            Task {
                await loadMorePhotosIfNeeded()
            }
        } else if currentIndex >= allPhotos.count {
            currentIndex = allPhotos.count - 1
            currentPhoto = allPhotos[currentIndex]
            // 触发增量加载
            Task {
                await loadMorePhotosIfNeeded()
            }
        } else {
            currentPhoto = allPhotos[currentIndex]
            // 触发增量加载
            if allPhotos.count <= loadMoreThreshold {
                Task {
                    await loadMorePhotosIfNeeded()
                }
            }
        }

        currentPhoto?.loadImage()
        persistSessionState()
    }

    /// 检查是否需要加载更多照片，如果需要则加载
    private func loadMorePhotosIfNeeded() async {
        guard !isLoadingMore else { return }
        guard allPhotos.count <= loadMoreThreshold else { return }

        do {
            try await loadMorePhotos()
        } catch {
            hasAttemptedSessionLoad = false
            errorMessage = error.localizedDescription
        }
    }

    /// 增量加载下一批照片
    private func loadMorePhotos() async throws {
        guard let activePreset else { return }
        guard !isLoadingMore else { return }
        guard !hasLoadedAllPhotos else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let policy = try decisionPolicy()

        var appendedAny = false
        let startOffset = fetchedPhotoCount
        var previousOffset = fetchedPhotoCount
        while !appendedAny && !hasLoadedAllPhotos {
            let page: PhotoLibraryService.PhotoFetchPage
            if activePreset == .smartGroup {
                page = try service.fetchPhotosPage(
                    withLocalIdentifiers: resumeCandidateIdentifiers ?? smartSessionIdentifiers,
                    limit: loadBatchSize,
                    offset: fetchedPhotoCount
                )
            } else {
                let excludeAlbums = effectiveExcludedAlbums()
                page = try service.fetchPhotosPage(
                    preset: activePreset,
                    sourceAlbum: selectedSourceAlbum,
                    limit: loadBatchSize,
                    offset: fetchedPhotoCount,
                    excludeAlbums: excludeAlbums
                )
            }

            fetchedPhotoCount = page.nextOffset
            if page.reachedEnd {
                hasLoadedAllPhotos = true
            }
            if fetchedPhotoCount <= previousOffset {
                // 防止极端情况下 offset 不前进导致死循环；若已到末尾则直接结束。
                break
            }
            previousOffset = fetchedPhotoCount

            let filteredAssets = page.assets.filter {
                policy.isEligible(
                    $0.localIdentifier,
                    for: cleanupIntent,
                    at: Date(),
                    skippedInCurrentSession: sessionProcessedIdentifiers
                )
            }
            if !filteredAssets.isEmpty {
                loadedPhotoCount += filteredAssets.count
                let newPhotos = filteredAssets.map { PhotoAsset(asset: $0) }
                allPhotos.append(contentsOf: newPhotos)
                appendedAny = true
            }

            if page.assets.isEmpty && page.reachedEnd {
                break
            }

            // 避免一次性扫太深导致卡顿；最多向后推进一定数量再让 UI 先恢复响应。
            if fetchedPhotoCount - startOffset >= 5000 {
                break
            }
        }

        // 如果当前没有照片，设置第一张
        if currentPhoto == nil && !allPhotos.isEmpty {
            currentIndex = 0
            currentPhoto = allPhotos.first
            currentPhoto?.loadImage()
        }

        persistSessionState()
    }

    private func pushUndo(action: UndoAction, assetIdentifier: String, index: Int) {
        undoStack.append(UndoEntry(action: action, assetIdentifier: assetIdentifier, index: index))
        canUndo = !undoStack.isEmpty
    }

    private func popUndo() -> UndoEntry? {
        guard !undoStack.isEmpty else { return nil }
        let entry = undoStack.removeLast()
        canUndo = !undoStack.isEmpty
        return entry
    }

    private func restorePhotoPosition(with assetIdentifier: String, fallbackIndex: Int) {
        guard !allPhotos.isEmpty else {
            currentIndex = 0
            currentPhoto = nil
            persistSessionState()
            return
        }

        if let matchedIndex = allPhotos.firstIndex(where: { $0.asset.localIdentifier == assetIdentifier }) {
            currentIndex = matchedIndex
        } else {
            currentIndex = min(max(0, fallbackIndex), allPhotos.count - 1)
        }

        currentPhoto = allPhotos[currentIndex]
        currentPhoto?.loadImage()
        persistSessionState()
    }

    private func restoreSessionState() {
        do {
            guard let state = try sessionRepository.load() else { return }
            applySessionState(state)
            hasAttemptedSessionLoad = false
        } catch {
            errorMessage = "无法读取上次会话: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func persistSessionState() -> Bool {
        guard let state = currentSessionState() else {
            clearPersistedSessionState()
            return true
        }

        do {
            try sessionRepository.save(state)
            return true
        } catch {
            errorMessage = "无法保存当前会话: \(error.localizedDescription)"
            return false
        }
    }

    private func clearPersistedSessionState() {
        sessionRepository.clear()
    }

    private func currentSessionState() -> CleanupSessionState? {
        guard let activeWorkflow, let activePreset else { return nil }
        return CleanupSessionState(
            workflow: activeWorkflow,
            preset: activePreset,
            selectedSourceAlbum: selectedSourceAlbum,
            selectedTargetAlbum: selectedTargetAlbum,
            initialCount: sessionInitialCount,
            markedDeleteCount: markedDeleteCount,
            keptCount: keptCount,
            movedCount: movedCount,
            estimatedDeletedBytes: estimatedDeletedBytes,
            pendingDeleteIdentifiers: pendingDeleteIdentifiers,
            smartSessionIdentifiers: smartSessionIdentifiers,
            hasCommittedPendingDeletes: hasCommittedPendingDeletes,
            processedIdentifiers: sessionProcessedIdentifiers.sorted()
        )
    }

    private func applySessionState(_ state: CleanupSessionState) {
        activeWorkflow = state.workflow
        activePreset = state.preset
        selectedSourceAlbum = state.selectedSourceAlbum
        selectedTargetAlbum = state.selectedTargetAlbum
        sessionInitialCount = state.initialCount
        markedDeleteCount = state.markedDeleteCount
        keptCount = state.keptCount
        movedCount = state.movedCount
        estimatedDeletedBytes = state.estimatedDeletedBytes
        pendingDeleteIdentifiers = state.pendingDeleteIdentifiers
        pendingDeleteCount = state.pendingDeleteIdentifiers.count
        smartSessionIdentifiers = state.smartSessionIdentifiers
        hasCommittedPendingDeletes = state.hasCommittedPendingDeletes
        sessionProcessedIdentifiers = Set(state.processedIdentifiers)
    }

    private var cleanupIntent: CleanupIntent {
        activeWorkflow == .organize ? .organize : .deleteCleanup
    }

    private func decisionPolicy() throws -> PhotoDecisionPolicy {
        PhotoDecisionPolicy(decisions: try decisionStore.decisions())
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
