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
    @Published private(set) var visionModels: [LMStudioModelDescriptor] = []
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
    private var controlTask: Task<Void, Never>?

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
        controlTask?.cancel()
    }

    var selectedTask: PhotoClassificationTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var runningTask: PhotoClassificationTask? {
        tasks.first(where: { $0.state == .running })
    }

    func bootstrap() async {
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
        writeStatusSnapshot()
        startControlInbox()
    }

    func requestPhotosPermission() async {
        authorizationStatus = await photoLibrary.requestAuthorization()
        await refreshAlbums()
    }

    func refreshEnvironment() async {
        authorizationStatus = photoLibrary.authorizationStatus
        await refreshAlbums()
        do {
            visionModels = try await lmStudio.installedVisionModels()
            if preferredModelIdentifier.isEmpty || !visionModels.contains(where: { $0.modelKey == preferredModelIdentifier }) {
                preferredModelIdentifier = visionModels.first?.modelKey ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(
        source: PhotoClassificationSourceScope,
        title: String,
        modelIdentifier: String,
        ordinaryScheme: PhotoClassificationScheme,
        screenshotScheme: PhotoClassificationScheme
    ) async -> UUID? {
        do {
            let assets = try photoLibrary.assets(for: source)
            let fingerprints = assets.map { asset in
                PhotoClassificationFingerprint(
                    assetIdentifier: asset.localIdentifier,
                    modificationDate: asset.modificationDate,
                    modelIdentifier: modelIdentifier,
                    analyzerVersion: Self.classificationAnalyzerVersion,
                    schemeIdentifier: isScreenshot(asset) ? screenshotScheme.id : ordinaryScheme.id,
                    schemeVersion: isScreenshot(asset) ? screenshotScheme.version : ordinaryScheme.version
                )
            }
            var targets = PhotoClassificationPlanner.defaultTargets(schemes: [ordinaryScheme, screenshotScheme])
            let currentAlbums = try photoLibrary.albums()
            for (identifier, target) in targets {
                guard case .newAlbum(let name) = target else { continue }
                let matching = currentAlbums.filter { $0.name == name }
                guard matching.count <= 1 else { throw MacPhotoLibraryError.ambiguousAlbumName(name) }
                if let album = matching.first {
                    targets[identifier] = .existingAlbum(identifier: album.id, name: album.name)
                }
            }
            let now = Date()
            let task = PhotoClassificationTask(
                id: UUID(),
                title: title,
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
        do {
            guard let url = URL(string: endpointText) else { throw LMStudioError.invalidEndpoint }
            lmStudio = try LMStudioClient(endpoint: url)
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
            guard let index = task.results.firstIndex(where: { $0.id == assetIdentifier }) else { return }
            task.results[index].reviewedCategoryIdentifier = categoryIdentifier
            if categoryIdentifier == nil {
                task.approvedAssetIdentifiers.remove(assetIdentifier)
            } else {
                task.approvedAssetIdentifiers.insert(assetIdentifier)
            }
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

    func apply(taskID: UUID) async {
        guard activeTask == nil, activeMutationTaskID == nil,
              let task = tasks.first(where: { $0.id == taskID }), task.state == .readyForReview else { return }
        activeMutationTaskID = taskID
        defer { activeMutationTaskID = nil }
        guard updateTask(id: taskID, mutation: { $0.state = .applying }) else { return }
        let previousMutations = task.mutations
        do {
            let additions = PhotoAlbumMutationPlanner.additions(
                results: task.results,
                approvedAssetIdentifiers: task.approvedAssetIdentifiers,
                targetsByCategory: task.targetsByCategory
            )
            let mutations = try await photoLibrary.apply(additions) { records in
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
            writeStatusSnapshot()
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

        do {
            try await lmStudio.ensureReady(modelIdentifier: task.modelIdentifier)
            try Task.checkCancellation()
            let currentAssets = try photoLibrary.assets(for: task.source)
            let assets = Dictionary(uniqueKeysWithValues: currentAssets.map { ($0.localIdentifier, $0) })
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
            let currentIdentifiers = Set(currentFingerprints.map(\.assetIdentifier))
            task.assetFingerprints = currentFingerprints
            task.results.removeAll { !currentIdentifiers.contains($0.id) }
            task.approvedAssetIdentifiers.formIntersection(currentIdentifiers)
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
                    modelIdentifier: task.modelIdentifier
                )
                try Task.checkCancellation()
                let result = PhotoClassificationResult(
                    fingerprint: fingerprint,
                    categoryIdentifier: response.categoryIdentifier,
                    reason: response.reason,
                    reviewedCategoryIdentifier: nil
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
        modelIdentifier: String
    ) async throws -> PhotoClassificationResponse {
        do {
            return try await lmStudio.classify(
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
        writeStatusSnapshot()
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

    private func writeStatusSnapshot() {
        let snapshot = GlimpseControlStatus(tasks: tasks)
        try? GlimpseControlFiles.write(snapshot)
    }

    private static func savedScheme(forKey key: String) -> PhotoClassificationScheme? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard var scheme = try? JSONDecoder().decode(PhotoClassificationScheme.self, from: data) else {
            return nil
        }
        if scheme.namespaceLegacyCategoryIdentifiers() {
            saveScheme(scheme, forKey: key)
        }
        return scheme
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

    private func startControlInbox() {
        guard controlTask == nil else { return }
        controlTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.consumeControlCommands()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func consumeControlCommands() async {
        do {
            for command in try GlimpseControlInbox().consume() {
                switch command.action {
                case .createRecent:
                    guard let days = command.recentDays,
                          [7, 30, 90].contains(days),
                          let modelIdentifier = command.modelIdentifier ?? visionModels.first?.modelKey else {
                        continue
                    }
                    if let taskID = await createTask(
                        source: .recentDays(days),
                        title: "最近 \(days) 天",
                        modelIdentifier: modelIdentifier,
                        ordinaryScheme: .ordinaryDefault,
                        screenshotScheme: .screenshotDefault
                    ) {
                        startOrContinue(taskID: taskID)
                    }
                case .continueTask:
                    if let taskID = command.taskID {
                        startOrContinue(taskID: taskID)
                    }
                case .reviewTask:
                    if let taskID = command.taskID {
                        selectedTaskID = taskID
                        isCreatingTask = false
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
