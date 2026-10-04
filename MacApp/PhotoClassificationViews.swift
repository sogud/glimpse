import AppKit
import Photos
import SwiftUI

struct GlimpseMacRootView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    @State private var taskPendingDeletion: PhotoClassificationTask?

    var body: some View {
        NavigationSplitView {
            List(selection: $coordinator.selectedTaskID) {
                Section("分类任务") {
                    ForEach(coordinator.tasks) { task in
                        TaskSidebarRow(task: task)
                            .tag(task.id)
                            .contextMenu {
                                Button("删除任务", role: .destructive) { taskPendingDeletion = task }
                                    .disabled(!coordinator.canDeleteTask(id: task.id))
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .navigationTitle("Glimpse")
            .toolbar {
                Button {
                    Task { await coordinator.refreshEnvironment() }
                } label: {
                    Label("刷新照片和模型状态", systemImage: "arrow.clockwise")
                }
                .disabled(!coordinator.canChangeEnvironment)
                Button {
                    coordinator.isCreatingTask = true
                } label: {
                    Label("新建分类任务", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        } detail: {
            detail
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("知道了") { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "未知错误")
        }
        .alert(
            "删除任务？",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            )
        ) {
            Button("取消", role: .cancel) { taskPendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let taskPendingDeletion {
                    coordinator.deleteTask(id: taskPendingDeletion.id)
                }
                taskPendingDeletion = nil
            }
        } message: {
            Text(
                taskPendingDeletion?.state == .applied
                    ? "删除后将同时失去本次整理的撤销记录。"
                    : "会删除任务进度和分类结果，不会修改 Apple Photos。"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await coordinator.refreshEnvironment() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if coordinator.authorizationStatus != .authorized && coordinator.authorizationStatus != .limited {
            PhotosPermissionView()
        } else if coordinator.isCreatingTask || coordinator.selectedTask == nil {
            NewClassificationTaskView()
        } else if let task = coordinator.selectedTask {
            switch task.state {
            case .readyForReview, .applying, .interrupted, .closed, .applied, .undone:
                ClassificationReviewView(task: task)
            case .draft, .running, .paused, .failed:
                ClassificationProgressView(task: task)
            }
        }
    }
}

private struct TaskSidebarRow: View {
    let task: PhotoClassificationTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .lineLimit(1)
            Text("\(task.progress.analyzed)/\(task.progress.total) · \(task.state.localizedTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

private struct PhotosPermissionView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator

    var body: some View {
        ContentUnavailableView {
            Label("需要 Apple Photos 权限", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("图片只交给本机模型识别。分析不会修改 Photos，只有复核并确认后才加入相册。iCloud 照片可能需要系统下载。")
        } actions: {
            if coordinator.authorizationStatus == .notDetermined {
                Button("授权访问") {
                    Task { await coordinator.requestPhotosPermission() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("打开系统设置") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                .buttonStyle(.borderedProminent)
                Text("在“隐私与安全性 → 照片”中允许 Glimpse 访问，再回到这里刷新。")
                    .font(.caption)
            }
        }
    }
}

private enum NewTaskSourceMode: String, CaseIterable, Identifiable {
    case allPhotos
    case recent7
    case recent30
    case recent90
    case album
    case dateRange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allPhotos: "全图库下一批"
        case .recent7: "最近 7 天"
        case .recent30: "最近 30 天"
        case .recent90: "最近 90 天"
        case .album: "指定相册"
        case .dateRange: "日期范围"
        }
    }
}

private struct NewClassificationTaskView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    @State private var sourceMode: NewTaskSourceMode = .allPhotos
    @State private var batchSize = 10
    @State private var albumIdentifier = ""
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        Form {
            Section {
                Label("本机识图 · 确认后才写相册", systemImage: "lock.shield")
                Text("可访问照片：\(coordinator.accessiblePhotoCount) 张\(coordinator.authorizationStatus == .limited ? "（仅授权范围）" : "")")
                    .monospacedDigit()
                Text("这是原生 App 的独立记录，不共享 CLI 分类进度。下一批会跳过已有结果及未完成任务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("照片范围") {
                Picker("来源", selection: $sourceMode) {
                    ForEach(NewTaskSourceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("本批数量", selection: $batchSize) {
                    Text("10 张 · 先试一批").tag(10)
                    Text("50 张").tag(50)
                    Text("100 张").tag(100)
                }
                Text("图片逐张串行分析；每次创建只处理这一批，不自动写入，也不会因继续任务增加新照片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if sourceMode == .album {
                    Picker("相册", selection: $albumIdentifier) {
                        Text("请选择").tag("")
                        ForEach(coordinator.albums) { album in
                            Text("\(album.name)（\(album.assetCount)）").tag(album.id)
                        }
                    }
                } else if sourceMode == .dateRange {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                }
            }

            modelSection

            ClassificationSchemeEditor(
                scheme: coordinator.savedOrdinaryScheme,
                onUpdate: { coordinator.updateSavedCategory(schemeKind: .ordinary, category: $0) },
                onDelete: { coordinator.removeSavedCategory(schemeKind: .ordinary, categoryIdentifier: $0) },
                onAdd: { coordinator.addSavedCategory(schemeKind: .ordinary) }
            )
            ClassificationSchemeEditor(
                scheme: coordinator.savedScreenshotScheme,
                onUpdate: { coordinator.updateSavedCategory(schemeKind: .screenshot, category: $0) },
                onDelete: { coordinator.removeSavedCategory(schemeKind: .screenshot, categoryIdentifier: $0) },
                onAdd: { coordinator.addSavedCategory(schemeKind: .screenshot) }
            )

            Section {
                HStack {
                    Spacer()
                    Button("创建下一批任务") {
                        Task {
                            guard let sourceAndTitle else { return }
                            _ = await coordinator.createTask(
                                source: sourceAndTitle.source,
                                title: sourceAndTitle.title,
                                modelIdentifier: coordinator.preferredModelIdentifier,
                                ordinaryScheme: coordinator.savedOrdinaryScheme,
                                screenshotScheme: coordinator.savedScreenshotScheme,
                                limit: batchSize
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canChangeEnvironment || sourceAndTitle == nil
                              || !coordinator.modelConnection.loadedModelIdentifiers.contains(coordinator.preferredModelIdentifier))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("整理下一批照片")
        .padding(.horizontal, 24)
        .onChange(of: coordinator.preferredModelIdentifier) { _, _ in coordinator.persistSchemePreferences() }
    }

    private var modelSection: some View {
        Section("LM Studio 本地模型") {
            HStack {
                TextField("本机地址", text: $coordinator.endpointText)
                Button("应用地址") { coordinator.updateEndpoint() }
                Button("刷新") { Task { await coordinator.refreshEnvironment() } }
            }
            switch coordinator.modelConnection {
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("正在检查本地服务…") }
            case .unavailable(let message):
                Label("本地服务未连接", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                Text(message).font(.caption).textSelection(.enabled)
                Text("请在 LM Studio 启动本地服务，加载已下载的视觉模型，再点击刷新。无需重新下载模型。")
                    .font(.caption).foregroundStyle(.secondary)
            case .connected(let models):
                Label("本地服务已连接", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                if models.isEmpty {
                    Text("服务没有返回支持图片输入的模型。请在 LM Studio 检查模型和 runtime，再刷新。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("视觉模型", selection: $coordinator.preferredModelIdentifier) {
                        Text("选择已加载实例").tag("")
                        ForEach(models) { model in
                            if model.loadedInstances.isEmpty {
                                Text("\(model.displayName) · 已下载，未加载").tag(model.key).disabled(true)
                            } else {
                                ForEach(model.loadedInstances) { instance in
                                    Text("\(model.displayName) · 已加载（\(instance.id)）").tag(instance.id)
                                }
                            }
                        }
                    }
                    if coordinator.modelConnection.loadedModelIdentifiers.isEmpty {
                        Text("模型已下载，但尚未加载。请在 LM Studio 加载后刷新。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Text("只连接本机回环地址；不自动下载、加载模型或切换模型重试。需要 LM Studio 0.4+。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!coordinator.canChangeEnvironment)
    }

    private var sourceAndTitle: (source: PhotoClassificationSourceScope, title: String)? {
        switch sourceMode {
        case .allPhotos:
            return (.allPhotos, "全图库下一批")
        case .recent7:
            return (.recentDays(7), "最近 7 天")
        case .recent30:
            return (.recentDays(30), "最近 30 天")
        case .recent90:
            return (.recentDays(90), "最近 90 天")
        case .album:
            guard let album = coordinator.albums.first(where: { $0.id == albumIdentifier }) else { return nil }
            return (.album(identifier: album.id, name: album.name), album.name)
        case .dateRange:
            guard startDate <= endDate else { return nil }
            return (.dateRange(start: startDate, end: endDate), "\(startDate.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))")
        }
    }
}

private struct ClassificationSchemeEditor: View {
    let scheme: PhotoClassificationScheme
    let onUpdate: (PhotoClassificationCategory) -> Void
    let onDelete: (PhotoClassificationCategoryID) -> Void
    let onAdd: () -> Void

    var body: some View {
        Section(scheme.name) {
            ForEach(scheme.categories) { category in
                ClassificationCategoryEditorRow(
                    category: category,
                    onUpdate: onUpdate,
                    onDelete: { onDelete(category.id) }
                )
            }
            Button("新增分类", systemImage: "plus", action: onAdd)
        }
    }
}

private struct ClassificationCategoryEditorRow: View {
    let category: PhotoClassificationCategory
    let onUpdate: (PhotoClassificationCategory) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Toggle(
                "",
                isOn: Binding(
                    get: { category.isEnabled },
                    set: { newValue in update { $0.isEnabled = newValue } }
                )
            )
            .labelsHidden()
            VStack {
                TextField(
                    "分类名称",
                    text: Binding(
                        get: { category.name },
                        set: { newValue in update { $0.name = newValue } }
                    )
                )
                TextField(
                    "判断说明",
                    text: Binding(
                        get: { category.classificationDescription },
                        set: { newValue in update { $0.classificationDescription = newValue } }
                    )
                )
                .font(.caption)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private func update(_ mutation: (inout PhotoClassificationCategory) -> Void) {
        var updated = category
        mutation(&updated)
        onUpdate(updated)
    }
}

private struct ClassificationProgressView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let task: PhotoClassificationTask
    private var progress: PhotoClassificationTaskProgress { task.progress }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: task.state == .running ? "sparkles" : "photo.stack")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text(task.title)
                .font(.largeTitle.bold())
            ProgressView(
                value: Double(progress.analyzed),
                total: Double(max(progress.total, 1))
            )
            .frame(maxWidth: 520)
            Text("已分析 \(progress.analyzed) / \(progress.total) 张")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("已有类别 \(progress.classified) · 待分类 \(progress.needsReview) · 未分析 \(progress.remaining)")
                .font(.callout).monospacedDigit()
            Text("分类结果只保存在本机，复核并确认后才写入 Apple Photos。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                if task.state == .running {
                    Button("暂停") { coordinator.pause(taskID: task.id) }
                } else if coordinator.activeTaskID == task.id {
                    ProgressView().controlSize(.small)
                    Text("正在暂停，等待当前请求退出…")
                } else {
                    Button(task.results.isEmpty ? "开始分类" : "继续分类") {
                        coordinator.startOrContinue(taskID: task.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(task.assetFingerprints.isEmpty)
                    .disabled(!coordinator.canChangeEnvironment)
                }
            }
            if task.assetFingerprints.isEmpty {
                Text("当前范围没有可分类的照片。")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct ClassificationReviewView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let task: PhotoClassificationTask
    @State private var selectedAssets = Set<String>()
    @State private var inspectedResult: PhotoClassificationResult?
    @State private var writeConfirmation: PhotoClassificationWriteConfirmation?
    @State private var confirmingUndo = false

    private var categories: [ReviewCategory] {
        task.ordinaryScheme.categories.filter(\.isEnabled).map {
            ReviewCategory(schemeName: task.ordinaryScheme.name, category: $0)
        } + task.screenshotScheme.categories.filter(\.isEnabled).map {
            ReviewCategory(schemeName: task.screenshotScheme.name, category: $0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(task.title).font(.title.bold())
                    Text("已分析 \(task.progress.analyzed) 张 · 待分类 \(task.progress.needsReview) 张 · \(task.state.localizedTitle)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if task.state == .readyForReview {
                    Button("复核后写入（\(task.writeConfirmation?.additions.count ?? 0) 张）") {
                        writeConfirmation = task.writeConfirmation
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(task.writeConfirmation == nil || !coordinator.canChangeEnvironment)
                } else if task.state == .applying {
                    ProgressView().controlSize(.small)
                    Text("正在更新 Apple Photos")
                } else if task.state == .applied {
                    Text("新增 \(task.mutations.count) 条相册归属").font(.caption)
                    Button("撤销本次整理") { confirmingUndo = true }
                        .disabled(task.mutations.isEmpty || !coordinator.canChangeEnvironment)
                } else if task.state == .interrupted {
                    Text("上次 Photos 操作中断，请先检查相册；此任务不能重试写入或撤销。")
                    Button("已检查，关闭任务") { coordinator.acknowledgeInterruptedWrite(taskID: task.id) }
                } else if task.state == .closed {
                    Text("已检查并关闭，历史记录保留。")
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                TargetAlbumMappingView(task: task, categories: categories)
                    .padding(20)
                    .disabled(!task.state.canReview)

                if !selectedAssets.isEmpty {
                    HStack {
                        Text("已选择 \(selectedAssets.count) 张")
                        Menu("移动到分类") {
                            ForEach(categories) { category in
                                Button(category.displayName) {
                                    moveSelected(to: category.id)
                                }
                            }
                            Divider()
                            Button("待分类") { moveSelected(to: nil) }
                        }
                        .disabled(!task.state.canReview)
                        Button("清除选择") { selectedAssets.removeAll() }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                ForEach(categories) { category in
                    ClassificationGroupSection(
                        task: task,
                        categoryIdentifier: category.id,
                        title: category.displayName,
                        results: task.results.filter { $0.effectiveCategoryIdentifier == category.id },
                        selectedAssets: $selectedAssets,
                        inspectedResult: $inspectedResult
                    )
                }
                ClassificationGroupSection(
                    task: task,
                    categoryIdentifier: nil,
                    title: "待分类",
                    results: task.results.filter { $0.effectiveCategoryIdentifier == nil },
                    selectedAssets: $selectedAssets,
                    inspectedResult: $inspectedResult
                )
            }
        }
        .sheet(item: $inspectedResult) { result in
            PhotoClassificationInspector(task: task, result: result)
                .environmentObject(coordinator)
        }
        .sheet(item: $writeConfirmation) { confirmation in
            PhotoWriteConfirmationView(confirmation: confirmation) {
                Task { await coordinator.apply(confirmation) }
            }
        }
        .alert("撤销本次整理", isPresented: $confirmingUndo) {
            Button("取消", role: .cancel) {}
            Button("撤销并保留空相册") {
                Task { await coordinator.undo(taskID: task.id, deleteEmptyCreatedAlbums: false) }
            }
            Button("撤销并删除本次创建的空相册", role: .destructive) {
                Task { await coordinator.undo(taskID: task.id, deleteEmptyCreatedAlbums: true) }
            }
        } message: {
            Text("只移除本任务新增的相册归属。")
        }
        .onAppear { selectedAssets.removeAll() }
        .onChange(of: task.id) { _, _ in selectedAssets.removeAll() }
        .onChange(of: task.state) { _, state in
            if !state.canReview { selectedAssets.removeAll(); writeConfirmation = nil }
        }
    }

    private func moveSelected(to categoryIdentifier: PhotoClassificationCategoryID?) {
        for assetIdentifier in selectedAssets {
            coordinator.updateCategory(
                taskID: task.id,
                assetIdentifier: assetIdentifier,
                categoryIdentifier: categoryIdentifier
            )
        }
        selectedAssets.removeAll()
    }
}

private struct PhotoWriteConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let confirmation: PhotoClassificationWriteConfirmation
    let onConfirm: () -> Void

    private var albums: [PhotoAlbumTarget] {
        confirmation.albumCounts.keys.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("确认写入 Apple Photos", systemImage: "photo.on.rectangle.angled")
                .font(.title2.bold())
            Text("将 \(confirmation.additions.count) 张照片加入 \(albums.count) 个相册。")
                .monospacedDigit()
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(albums, id: \.self) { album in
                        HStack {
                            Text(album.displayName)
                            Spacer()
                            Text("\(confirmation.albumCounts[album] ?? 0) 张").monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            Text("只新增相册归属，不删除照片，不移除原有归属。“待删除”仍然只是需要人工检查的建议。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确认写入") { dismiss(); onConfirm() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private extension PhotoAlbumTarget {
    var displayName: String {
        switch self {
        case .newAlbum(let name), .existingAlbum(_, let name): name
        case .skip: "本次跳过"
        }
    }
}

private struct TargetAlbumMappingView: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let task: PhotoClassificationTask
    let categories: [ReviewCategory]

    var body: some View {
        DisclosureGroup("目标相册映射") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(categories) { category in
                    GridRow {
                        Text(category.displayName)
                        Picker(
                            "",
                            selection: Binding(
                                get: { task.targetsByCategory[category.id] ?? .skip },
                                set: { coordinator.setTarget(taskID: task.id, categoryIdentifier: category.id, target: $0) }
                            )
                        ) {
                            Text("新建“\(PhotoClassificationPlanner.albumName(schemeName: category.schemeName, category: category.category))”").tag(
                                PhotoAlbumTarget.newAlbum(name: PhotoClassificationPlanner.albumName(schemeName: category.schemeName, category: category.category))
                            )
                            ForEach(coordinator.albums) { album in
                                Text("已有：\(album.name)（\(album.assetCount) 张 · \(album.id.prefix(8))）").tag(
                                    PhotoAlbumTarget.existingAlbum(identifier: album.id, name: album.name)
                                )
                            }
                            Divider()
                            Text("本次跳过").tag(PhotoAlbumTarget.skip)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 360)
                    }
                }
            }
            .padding(.top, 10)
            Text("同名相册不唯一时默认跳过，请明确选择目标。相册名、现有数量和标识用于区分同名项。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ClassificationGroupSection: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let task: PhotoClassificationTask
    let categoryIdentifier: PhotoClassificationCategoryID?
    let title: String
    let results: [PhotoClassificationResult]
    @Binding var selectedAssets: Set<String>
    @Binding var inspectedResult: PhotoClassificationResult?

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 14)]

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.title2.bold())
                    Text("\(results.count)").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(results) { result in
                        if task.state.canReview {
                            card(for: result).draggable(result.id)
                        } else {
                            card(for: result)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .dropDestination(for: String.self) { identifiers, _ in
                guard task.state.canReview else { return false }
                var accepted = false
                for identifier in identifiers {
                    guard let result = task.results.first(where: { $0.id == identifier }),
                          let scheme = task.scheme(for: result) else { continue }
                    if let categoryIdentifier,
                       !scheme.categories.contains(where: { $0.id == categoryIdentifier && $0.isEnabled }) { continue }
                    coordinator.updateCategory(
                        taskID: task.id,
                        assetIdentifier: identifier,
                        categoryIdentifier: categoryIdentifier
                    )
                    accepted = true
                }
                return accepted
            }
        }
    }

    private func card(for result: PhotoClassificationResult) -> some View {
        PhotoClassificationCard(
            task: task, result: result, isSelected: selectedAssets.contains(result.id),
            onToggleSelection: {
                if selectedAssets.contains(result.id) { selectedAssets.remove(result.id) }
                else { selectedAssets.insert(result.id) }
            },
            onInspect: { inspectedResult = result }
        )
    }
}

private struct PhotoClassificationCard: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let task: PhotoClassificationTask
    let result: PhotoClassificationResult
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onInspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncPhotoThumbnail(assetIdentifier: result.id, longestEdge: 420)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture(perform: onInspect)
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
                .padding(8)
                .disabled(!task.state.canReview)
                .accessibilityLabel(isSelected ? "取消批量选择" : "选择照片")
            }
            Text(task.scheme(for: result)?.name ?? "未知方案")
                .font(.caption.weight(.medium)).foregroundStyle(.tint)
            Text(result.reason)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Picker("分类", selection: Binding(
                get: { result.effectiveCategoryIdentifier },
                set: { coordinator.updateCategory(taskID: task.id, assetIdentifier: result.id, categoryIdentifier: $0) }
            )) {
                Text("待分类").tag(PhotoClassificationCategoryID?.none)
                ForEach(task.scheme(for: result)?.categories.filter(\.isEnabled) ?? []) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .labelsHidden()
            .disabled(!task.state.canReview)
            Toggle("写入相册", isOn: Binding(
                get: { task.approvedAssetIdentifiers.contains(result.id) },
                set: { coordinator.setApproved(taskID: task.id, assetIdentifier: result.id, approved: $0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!task.state.canReview || result.effectiveCategoryIdentifier == nil)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PhotoClassificationInspector: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    @Environment(\.dismiss) private var dismiss
    let task: PhotoClassificationTask
    let result: PhotoClassificationResult

    private var currentTask: PhotoClassificationTask { coordinator.tasks.first(where: { $0.id == task.id }) ?? task }
    private var currentResult: PhotoClassificationResult { currentTask.results.first(where: { $0.id == result.id }) ?? result }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("分类详情").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
            }
            AsyncPhotoThumbnail(assetIdentifier: result.id, longestEdge: 1200)
                .frame(maxWidth: 900, maxHeight: 600)
            Text(currentResult.reason).foregroundStyle(.secondary)
            Picker("主分类", selection: Binding(
                get: { currentResult.effectiveCategoryIdentifier },
                set: { coordinator.updateCategory(taskID: task.id, assetIdentifier: result.id, categoryIdentifier: $0) }
            )) {
                Text("待分类").tag(PhotoClassificationCategoryID?.none)
                ForEach(currentTask.scheme(for: currentResult)?.categories.filter(\.isEnabled) ?? []) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .frame(maxWidth: 320)
            .disabled(!currentTask.state.canReview)
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
    }
}

private struct ReviewCategory: Identifiable {
    let schemeName: String
    let category: PhotoClassificationCategory

    var id: PhotoClassificationCategoryID { category.id }
    var displayName: String { "\(schemeName) · \(category.name)" }
}

private struct AsyncPhotoThumbnail: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let assetIdentifier: String
    let longestEdge: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    ProgressView()
                }
            }
        }
        .task(id: assetIdentifier) {
            image = await coordinator.thumbnail(assetIdentifier: assetIdentifier, longestEdge: longestEdge)
        }
    }
}

private extension PhotoClassificationTaskState {
    var localizedTitle: String {
        switch self {
        case .draft: "待开始"
        case .running: "分类中"
        case .paused: "已暂停"
        case .readyForReview: "待复核"
        case .applying: "写入中"
        case .interrupted: "写入中断，需检查"
        case .closed: "已检查并关闭"
        case .applied: "已整理"
        case .undone: "已撤销"
        case .failed: "失败"
        }
    }
}
