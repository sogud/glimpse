import Foundation
import Photos

enum SmartAnalysisViewState: Equatable {
    case idle
    case permissionRequired
    case scanning
    case completed
    case failed(String)
}

/// 智能 Tab 的界面状态，不参与任何照片库修改操作。
@MainActor
final class SmartAnalysisViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: PhotoLibraryService.AuthorizationStatus = .notDetermined
    @Published private(set) var state: SmartAnalysisViewState = .idle
    @Published private(set) var progress: SmartAnalysisProgress?
    @Published private(set) var groups: [SmartInsightGroup] = []
    @Published private(set) var totalAssetCount = 0
    @Published private(set) var analyzedAssetCount = 0
    @Published private(set) var lastScanDate: Date?

    private let service: SmartPhotoAnalysisService
    private var scanTask: Task<Void, Never>?
    private var needsIncrementalRefresh = false

    init(service: SmartPhotoAnalysisService? = nil) {
        self.service = service ?? SmartPhotoAnalysisService()
        self.service.onPhotoLibraryChange = { [weak self] in
            self?.needsIncrementalRefresh = true
        }
        refreshAuthorizationStatus()
        loadCachedSnapshot()
    }

    deinit {
        scanTask?.cancel()
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var isScanning: Bool {
        if case .scanning = state {
            return true
        }
        return false
    }

    var permissionStatusText: String {
        switch authorizationStatus {
        case .authorized:
            return "完整访问"
        case .limited:
            return "有限访问"
        case .denied:
            return "未授权"
        case .notDetermined:
            return "未决定"
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = service.currentAuthorizationStatus()
        if !isAuthorized {
            state = .permissionRequired
        } else if groups.isEmpty {
            state = .idle
        } else if needsIncrementalRefresh && !isScanning {
            needsIncrementalRefresh = false
            startScan()
        }
    }

    func loadCachedSnapshot() {
        guard let snapshot = service.loadCachedSnapshot() else { return }
        apply(snapshot: snapshot)
        state = snapshot.groups.isEmpty ? .idle : .completed
    }

    func requestPermissionAndScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            let status = await service.requestAuthorization()
            authorizationStatus = status
            guard isAuthorized else {
                state = .permissionRequired
                return
            }
            startScan()
        }
    }

    func startScan() {
        guard !isScanning else { return }
        guard isAuthorized else {
            state = .permissionRequired
            return
        }

        scanTask?.cancel()
        state = .scanning
        progress = SmartAnalysisProgress(
            phase: .metadata,
            processed: 0,
            total: max(totalAssetCount, 1),
            message: "准备本地分析",
            groups: groups
        )

        scanTask = Task { [weak self] in
            guard let self else { return }

            do {
                let snapshot = try await service.analyzeLocalPhotoLibrary { [weak self] nextProgress in
                    await MainActor.run {
                        guard let self else { return }
                        self.progress = nextProgress
                        if !nextProgress.groups.isEmpty || nextProgress.phase == .completed {
                            self.groups = nextProgress.groups
                        }
                    }
                }

                guard !Task.isCancelled else { return }
                apply(snapshot: snapshot)
                state = .completed
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                state = groups.isEmpty ? .idle : .completed
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        state = groups.isEmpty ? .idle : .completed
    }

    private func apply(snapshot: SmartAnalysisSnapshot) {
        groups = snapshot.groups
        totalAssetCount = snapshot.totalAssetCount
        analyzedAssetCount = snapshot.recordsByIdentifier.count
        lastScanDate = snapshot.scannedAt
        progress = SmartAnalysisProgress(
            phase: .completed,
            processed: snapshot.totalAssetCount,
            total: snapshot.totalAssetCount,
            message: "分析完成",
            groups: snapshot.groups
        )
    }
}
