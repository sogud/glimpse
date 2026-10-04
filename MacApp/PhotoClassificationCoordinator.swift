import AppKit
import Foundation
import Photos
import SwiftData
import UserNotifications

@MainActor
final class PhotoClassificationCoordinator: ObservableObject {
    private static let classificationAnalyzerVersion = 2

    @Published private(set) var tasks: [PhotoClassificationTask] = []
    @Published private(set) var albums: [PhotoAlbumDescriptor] = []
    @Published private(set) var modelConnection: LMStudioConnectionState = .checking
    @Published private(set) var isRefreshingEnvironment = false
    @Published private(set) var accessiblePhotoCount = 0
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published var selectedTaskID: UUID?
    @Published var isCreatingTask = false
    @Published var errorMessage: String?
    @Published var endpointText: String
    @Published var preferredModelIdentifier: String
    @Published var savedOrdinaryScheme: PhotoClassificationScheme
    @Published var savedScreenshotScheme: PhotoClassificationScheme

    private let photoLibrary = MacPhotoLibraryService()
    private let taskStore: PhotoClassificationTaskStore
    private var lmStudio: LMStudioClient
    private var activeTask: Task<Void, Never>?
    @Published private(set) var activeTaskID: UUID?
    private var activeMutationTaskID: UUID?
    private var hasBootstrapped = false

    convenience init() {
        self.init(container: PhotoSortDataContainer.shared)
    }

    init(container: ModelContainer) {
        let defaults = UserDefaults.standard
        let defaultEndpoint = "http://127.0.0.1:1234/v1"
        let savedEndpoint = defaults.string(forKey: "lmStudioEndpoint") ?? defaultEndpoint
        let endpointURL = URL(string: savedEndpoint)
        let client = endpointURL.flatMap { try? LMStudioClient(endpoint: $0) }
        endpointText = client == nil ? defaultEndpoint : savedEndpoint
        preferredModelIdentifier = defaults.string(forKey: "lmStudioModel") ?? ""
        savedOrdinaryScheme = Self.savedScheme(forKey: "ordinaryClassificationScheme") ?? .ordinaryDefault
        savedScreenshotScheme = Self.savedScheme(forKey: "screenshotClassificationScheme") ?? .screenshotDefault
        taskStore = PhotoClassificationTaskStore(container: container)
        lmStudio = client ?? (try! LMStudioClient(endpoint: URL(string: defaultEndpoint)!))
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    deinit {
        activeTask?.cancel()
    }

    var selectedTask: PhotoClassificationTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var runningTask: PhotoClassificationTask? {
        tasks.first(where: { $0.state == .running })
    }

    var canChangeEnvironment: Bool { activeTask == nil && activeMutationTaskID == nil && !isRefreshingEnvironment }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        do {
            tasks = try taskStore.tasks()
            for index in tasks.indices {
                let recovered = tasks[index].state.recoveredAfterInterruption
                if recovered != tasks[index].state {
                    tasks[index].state = recovered
                    try taskStore.save(tasks[index])
                }
            }
            selectedTaskID = selectedTaskID ?? tasks.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEnvironment()
        requestNotificationPermission()
    }

    func requestPhotosPermission() async {
        authorizationStatus = await photoLibrary.requestAuthorization()
        await refreshEnvironment()
    }

    func refreshEnvironment() async {
        guard canChangeEnvironment else { return }
        isRefreshingEnvironment = true
        defer { isRefreshingEnvironment = false }
        authorizationStatus = photoLibrary.authorizationStatus
        await refreshAlbums()
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            do { accessiblePhotoCount = try photoLibrary.assets(for: .allPhotos).count }
            catch { errorMessage = error.localizedDescription }
        } else {
            accessiblePhotoCount = 0
        }
        modelConnection = .checking
        do {
            let models = try await lmStudio.visionModels()
            modelConnection = .connected(models)
            if !modelConnection.loadedModelIdentifiers.contains(preferredModelIdentifier) {
                preferredModelIdentifier = modelConnection.loadedModelIdentifiers.first ?? ""
            }
        } catch {
            modelConnection = .unavailable(error.localizedDescription)
        }
    }

    func createTask(
        source: PhotoClassificationSourceScope,
        title: String,
        modelIdentifier: String,
        ordinaryScheme: PhotoClassificationScheme,
        screenshotScheme: PhotoClassificationScheme,
        limit: Int = 10
    ) async -> UUID? {
        do {
            guard canChangeEnvironment else {
                errorMessage = "请先暂停当前分类并等待请求结束，再创建下一批。"
                return nil
            }
            guard modelConnection.loadedModelIdentifiers.contains(modelIdentifier) else {
                throw LMStudioError.modelNotLoaded(modelIdentifier)
            }
            let assets = try photoLibrary.assets(for: source)
            let currentFingerprints = assets.map { asset in
                PhotoClassificationFingerprint(
                    assetIdentifier: asset.localIdentifier,
                    modificationDate: asset.modificationDate,
                    modelIdentifier: modelIdentifier,
                    analyzerVersion: Self.classificationAnalyzerVersion,
                    schemeIdentifier: isScreenshot(asset) ? screenshotScheme.id : ordinaryScheme.id,
                    schemeVersion: isScreenshot(asset) ? screenshotScheme.version : ordinaryScheme.version
                )
            }
            let history = try taskStore.tasks()
            let fingerprints = try PhotoClassificationPlanner.nextBatch(
                current: currentFingerprints, cached: history.flatMap(\.results),
                reserved: history.flatMap { $0.state.reservesPhotos ? $0.assetFingerprints : [] }, limit: limit
            )
            guard !fingerprints.isEmpty else {
                errorMessage = "这个范围没有下一批待分析照片。已有结果或未完成任务占用了这些照片，请先复核或继续已有任务。"
                return nil
            }
            let targets = PhotoClassificationPlanner.defaultTargets(
                schemes: [ordinaryScheme, screenshotScheme], existingAlbums: try photoLibrary.albums()
            )
            let now = Date()
            let task = PhotoClassificationTask(
                id: UUID(),
                title: "\(title) · \(fingerprints.count) 张",
                source: source,
                state: .draft,
                modelIdentifier: modelIdentifier,
                ordinaryScheme: ordinaryScheme,
                screenshotScheme: screenshotScheme,
                assetFingerprints: fingerprints,
                results: [],
                targetsByCategory: targets,
                approvedAssetIdentifiers: [],
                mutations: [],
                createdAt: now,
                updatedAt: now
            )
            try taskStore.save(task)
            preferredModelIdentifier = modelIdentifier
            savedOrdinaryScheme = ordinaryScheme
            savedScreenshotScheme = screenshotScheme
            let defaults = UserDefaults.standard
            defaults.set(modelIdentifier, forKey: "lmStudioModel")
            Self.saveScheme(ordinaryScheme, forKey: "ordinaryClassificationScheme")
            Self.saveScheme(screenshotScheme, forKey: "screenshotClassificationScheme")
            upsert(task)
            selectedTaskID = task.id
            isCreatingTask = false
            return task.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func startOrContinue(taskID: UUID) {
        guard activeTask == nil,
              activeMutationTaskID == nil,
              tasks.first(where: { $0.id == taskID })?.state.canStartOrContinueInference == true else { return }
        activeTaskID = taskID
        activeTask = Task { [weak self] in
            await self?.run(taskID: taskID)
            self?.activeTask = nil
            self?.activeTaskID = nil
        }
    }

    func updateEndpoint() {
        guard canChangeEnvironment else {
            errorMessage = "分类或相册写入期间不能切换模型地址。"
            return
        }
        do {
            guard let url = URL(string: endpointText) else { throw LMStudioError.invalidEndpoint }
            lmStudio = try LMStudioClient(endpoint: url)
            modelConnection = .checking
            UserDefaults.standard.set(endpointText, forKey: "lmStudioEndpoint")
            Task { await refreshEnvironment() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistSchemePreferences() {
        Self.saveScheme(savedOrdinaryScheme, forKey: "ordinaryClassificationScheme")
        Self.saveScheme(savedScreenshotScheme, forKey: "screenshotClassificationScheme")
        UserDefaults.standard.set(preferredModelIdentifier, forKey: "lmStudioModel")
    }

    func pause(taskID: UUID) {
        guard activeTaskID == taskID else { return }
        activeTask?.cancel()
        updateTask(id: taskID) { task in
            task.state = .paused
        }
    }

    func updateCategory(
        taskID: UUID,
        assetIdentifier: String,
        categoryIdentifier: PhotoClassificationCategoryID?
    ) {
        guard tasks.first(where: { $0.id == taskID })?.state.canReview == true else { return }
        updateTask(id: taskID) { task in
            task.reviewCategory(assetIdentifier: assetIdentifier, categoryIdentifier: categoryIdentifier)
        }
    }

    func setApproved(taskID: UUID, assetIdentifier: String, approved: Bool) {
        guard tasks.first(where: { $0.id == taskID })?.state.canReview == true else { return }
        updateTask(id: taskID) { task in
            if approved {
                task.approvedAssetIdentifiers.insert(assetIdentifier)
            } else {
                task.approvedAssetIdentifiers.remove(assetIdentifier)
            }
        }
    }

    func setTarget(
        taskID: UUID,
        categoryIdentifier: PhotoClassificationCategoryID,
        target: PhotoAlbumTarget
    ) {
        guard tasks.first(where: { $0.id == taskID })?.state.canReview == true else { return }
        updateTask(id: taskID) { task in
            task.targetsByCategory[categoryIdentifier] = target
        }
    }

    func apply(_ confirmation: PhotoClassificationWriteConfirmation) async {
        let taskID = confirmation.id
        guard activeTask == nil, activeMutationTaskID == nil,
              let task = tasks.first(where: { $0.id == taskID }), task.state == .readyForReview else { return }
        guard confirmation.matches(task) else {
            errorMessage = "复核内容已经改变，请重新检查相册清单并确认写入。"
            return
        }
        activeMutationTaskID = taskID
        defer { activeMutationTaskID = nil }
        guard updateTask(id: taskID, mutation: { $0.state = .applying }) else { return }
        let previousMutations = task.mutations
        do {
            let mutations = try await photoLibrary.apply(confirmation.additions) { records in
                guard self.updateTask(id: taskID, mutation: { $0.mutations = previousMutations + records }) else {
                    throw MacPhotoLibraryError.partialApply(records: records, message: "无法保存相册写入记录")
                }
            }
            updateTask(id: taskID) { task in
                task.mutations = previousMutations + mutations
                task.state = .applied
            }
            await refreshAlbums()
        } catch MacPhotoLibraryError.partialApply(let records, let message) {
            updateTask(id: taskID) { task in
                task.mutations = previousMutations + records
                task.state = .interrupted
            }
            errorMessage = "部分照片已经写入，当前相册结果未知；请检查 Photos 后再继续：\(message)"
            await refreshAlbums()
        } catch {
            updateTask(id: taskID) { $0.state = .interrupted }
            errorMessage = error.localizedDescription
        }
    }

    func undo(taskID: UUID, deleteEmptyCreatedAlbums: Bool) async {
        guard activeMutationTaskID == nil, activeTask == nil,
              let task = tasks.first(where: { $0.id == taskID }), task.state == .applied else { return }
        activeMutationTaskID = taskID
        defer { activeMutationTaskID = nil }
        guard updateTask(id: taskID, mutation: { $0.state = .applying }) else { return }
        do {
            try await photoLibrary.undo(task.mutations, deleteEmptyCreatedAlbums: deleteEmptyCreatedAlbums)
            updateTask(id: taskID) { $0.state = .undone }
            await refreshAlbums()
        } catch {
            updateTask(id: taskID) { $0.state = .interrupted }
            errorMessage = error.localizedDescription
        }
    }

    func canDeleteTask(id: UUID) -> Bool {
        tasks.first(where: { $0.id == id })?.state.canDelete == true
            && activeTaskID != id && activeMutationTaskID != id
    }

    func acknowledgeInterruptedWrite(taskID: UUID) {
        guard activeMutationTaskID == nil, tasks.first(where: { $0.id == taskID })?.state == .interrupted else { return }
        updateTask(id: taskID) { $0.state = $0.state.afterManualInspection }
    }

    func deleteTask(id: UUID) {
        guard canDeleteTask(id: id) else {
            errorMessage = "任务仍在运行或写入结果未知，请先完成操作并检查 Photos。"
            return
        }
        do {
            try taskStore.delete(id: id)
            tasks.removeAll { $0.id == id }
            if selectedTaskID == id {
                selectedTaskID = tasks.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSavedCategory(
        schemeKind: PhotoClassificationSchemeKind,
        category: PhotoClassificationCategory
    ) {
        mutateSavedScheme(kind: schemeKind) { $0.updateCategory(category) }
    }

    func addSavedCategory(schemeKind: PhotoClassificationSchemeKind) {
        let category = PhotoClassificationCategory(
            id: PhotoClassificationCategoryID(
                schemeKind: schemeKind,
                localIdentifier: UUID().uuidString.lowercased()
            ),
            name: "新分类",
            classificationDescription: "",
            isEnabled: true
        )
        mutateSavedScheme(kind: schemeKind) { $0.appendCategory(category) }
    }

    func removeSavedCategory(
        schemeKind: PhotoClassificationSchemeKind,
        categoryIdentifier: PhotoClassificationCategoryID
    ) {
        mutateSavedScheme(kind: schemeKind) { $0.removeCategory(id: categoryIdentifier) }
    }

    func thumbnail(assetIdentifier: String, longestEdge: CGFloat = 320) async -> NSImage? {
        guard let asset = photoLibrary.assets(localIdentifiers: [assetIdentifier])[assetIdentifier] else {
            return nil
        }
        return try? await photoLibrary.thumbnail(for: asset, longestEdge: longestEdge)
    }

    private func run(taskID: UUID) async {
        guard var task = tasks.first(where: { $0.id == taskID }),
              task.state.canStartOrContinueInference else { return }
        task.state = .running
        guard updateTask(id: taskID, mutation: { $0.state = .running }) else { return }
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Glimpse 正在执行本地照片分类"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let client = lmStudio

        do {
            try await client.ensureReady(modelIdentifier: task.modelIdentifier)
            try Task.checkCancellation()
            let assets = photoLibrary.assets(localIdentifiers: task.assetFingerprints.map(\.assetIdentifier))
            let currentAssets = task.assetFingerprints.compactMap { assets[$0.assetIdentifier] }
            let currentFingerprints = currentAssets.map { asset in
                PhotoClassificationFingerprint(
                    assetIdentifier: asset.localIdentifier,
                    modificationDate: asset.modificationDate,
                    modelIdentifier: task.modelIdentifier,
                    analyzerVersion: Self.classificationAnalyzerVersion,
                    schemeIdentifier: isScreenshot(asset) ? task.screenshotScheme.id : task.ordinaryScheme.id,
                    schemeVersion: isScreenshot(asset) ? task.screenshotScheme.version : task.ordinaryScheme.version
                )
            }
            task.refreshBatch(currentFingerprints)
            task.updatedAt = Date()
            let cachedResults = try taskStore.tasks().flatMap(\.results)
            let existingFingerprints = Set(task.results.map(\.fingerprint))
            let reusableResults = PhotoClassificationPlanner.reusableResults(
                current: currentFingerprints.filter { !existingFingerprints.contains($0) },
                cached: cachedResults
            )
            for result in reusableResults {
                if let index = task.results.firstIndex(where: { $0.id == result.id }) {
                    task.results[index] = result
                } else {
                    task.results.append(result)
                }
                if result.categoryIdentifier == nil {
                    task.approvedAssetIdentifiers.remove(result.id)
                } else {
                    task.approvedAssetIdentifiers.insert(result.id)
                }
            }
            try Task.checkCancellation()
            try taskStore.save(task)
            upsert(task)
            let pending = PhotoClassificationPlanner.assetsRequiringClassification(
                current: currentFingerprints,
                cached: task.results
            )

            for fingerprint in pending {
                try Task.checkCancellation()
                guard let asset = assets[fingerprint.assetIdentifier] else { continue }
                let screenshot = isScreenshot(asset)
                let scheme = screenshot ? task.screenshotScheme : task.ordinaryScheme
                let jpegData = try await photoLibrary.jpegData(for: asset)
                try Task.checkCancellation()
                let ocrText = screenshot ? await photoLibrary.recognizedText(for: jpegData) : nil
                try Task.checkCancellation()
                let response = try await classify(
                    jpegData: jpegData,
                    ocrText: ocrText,
                    scheme: scheme,
                    modelIdentifier: task.modelIdentifier,
                    client: client
                )
                try Task.checkCancellation()
                let result = PhotoClassificationResult(
                    fingerprint: fingerprint,
                    categoryIdentifier: response.categoryIdentifier,
                    reason: response.reason
                )
                if let index = task.results.firstIndex(where: { $0.id == result.id }) {
                    task.results[index] = result
                } else {
                    task.results.append(result)
                }
                if result.categoryIdentifier != nil {
                    task.approvedAssetIdentifiers.insert(result.id)
                } else {
                    task.approvedAssetIdentifiers.remove(result.id)
                }
                task.updatedAt = Date()
                try taskStore.save(task)
                upsert(task)
            }

            try Task.checkCancellation()
            task.state = .readyForReview
            task.updatedAt = Date()
            try taskStore.save(task)
            upsert(task)
            sendNotification(title: "Glimpse 分类完成", body: "\(task.title) 已可以复核")
        } catch is CancellationError {
            updateTask(id: taskID) { $0.state = .paused }
        } catch {
            updateTask(id: taskID) { $0.state = .paused }
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
            sendNotification(title: "Glimpse 已暂停", body: error.localizedDescription)
        }
    }

    private func classify(
        jpegData: Data,
        ocrText: String?,
        scheme: PhotoClassificationScheme,
        modelIdentifier: String,
        client: LMStudioClient
    ) async throws -> PhotoClassificationResponse {
        do {
            return try await client.classify(
                jpegData: jpegData,
                ocrText: ocrText,
                scheme: scheme,
                modelIdentifier: modelIdentifier
            )
        } catch is PhotoClassificationResponseError {
            return PhotoClassificationResponse(categoryIdentifier: nil, reason: "模型结果无效，需要手动分类")
        }
    }

    private func refreshAlbums() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            albums = []
            return
        }
        do {
            albums = try photoLibrary.albums()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func updateTask(id: UUID, mutation: (inout PhotoClassificationTask) -> Void) -> Bool {
        guard var task = tasks.first(where: { $0.id == id }) else { return false }
        mutation(&task)
        task.updatedAt = Date()
        do {
            try taskStore.save(task)
            upsert(task)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func upsert(_ task: PhotoClassificationTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        tasks.sort { $0.updatedAt > $1.updatedAt }
    }

    private func isScreenshot(_ asset: PHAsset) -> Bool {
        asset.mediaSubtypes.contains(.photoScreenshot)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private static func savedScheme(forKey key: String) -> PhotoClassificationScheme? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PhotoClassificationScheme.self, from: data)
    }

    private static func saveScheme(_ scheme: PhotoClassificationScheme, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(scheme), forKey: key)
    }

    private func mutateSavedScheme(
        kind: PhotoClassificationSchemeKind,
        mutation: (inout PhotoClassificationScheme) -> Void
    ) {
        switch kind {
        case .ordinary:
            mutation(&savedOrdinaryScheme)
            Self.saveScheme(savedOrdinaryScheme, forKey: "ordinaryClassificationScheme")
        case .screenshot:
            mutation(&savedScreenshotScheme)
            Self.saveScheme(savedScreenshotScheme, forKey: "screenshotClassificationScheme")
        }
    }

}
