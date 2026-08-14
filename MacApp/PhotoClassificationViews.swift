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
                            }
                    }
                }
            }
            .navigationTitle("Glimpse")
            .toolbar {
                Button {
                    coordinator.isCreatingTask = true
                } label: {
                    Label("新建分类任务", systemImage: "plus")
                }
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
    }

    @ViewBuilder
    private var detail: some View {
        if coordinator.authorizationStatus != .authorized && coordinator.authorizationStatus != .limited {
            PhotosPermissionView()
        } else if coordinator.isCreatingTask || coordinator.selectedTask == nil {
            NewClassificationTaskView()
        } else if let task = coordinator.selectedTask {
            switch task.state {
            case .readyForReview, .applying, .applied, .undone:
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
            Text("\(task.results.count)/\(task.assetFingerprints.count) · \(task.state.localizedTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Text("Glimpse 只在本机读取缩略图，并且只在你确认后向相册添加照片。")
        } actions: {
            Button("授权访问") {
                Task { await coordinator.requestPhotosPermission() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private enum NewTaskSourceMode: String, CaseIterable, Identifiable {
    case recent7
    case recent30
    case recent90
    case album
    case dateRange

    var id: String { rawValue }

    var title: String {
        switch self {
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
    @State private var sourceMode: NewTaskSourceMode = .recent7
    @State private var albumIdentifier = ""
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        Form {
            Section("照片范围") {
                Picker("来源", selection: $sourceMode) {
                    ForEach(NewTaskSourceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
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

            Section("本地模型") {
                HStack {
                    TextField("LM Studio 地址", text: $coordinator.endpointText)
                    Button("应用") { coordinator.updateEndpoint() }
                }
                if coordinator.visionModels.isEmpty {
                    ContentUnavailableView(
                        "没有发现多模态模型",
                        systemImage: "brain.head.profile",
                        description: Text("请先在 LM Studio 下载支持图片输入的模型。")
                    )
                } else {
                    Picker("模型", selection: $coordinator.preferredModelIdentifier) {
                        Text("请选择").tag("")
                        ForEach(coordinator.visionModels) { model in
                            Text(model.displayName).tag(model.modelKey)
                        }
                    }
                }
                Text("开始任务时才会启动 LM Studio；推理只连接 localhost。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    Button("创建任务") {
                        Task {
                            guard let sourceAndTitle else { return }
                            _ = await coordinator.createTask(
                                source: sourceAndTitle.source,
                                title: sourceAndTitle.title,
                                modelIdentifier: coordinator.preferredModelIdentifier,
                                ordinaryScheme: coordinator.savedOrdinaryScheme,
                                screenshotScheme: coordinator.savedScreenshotScheme
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator.preferredModelIdentifier.isEmpty || sourceAndTitle == nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("新建分类任务")
        .padding(.horizontal, 24)
        .onChange(of: coordinator.preferredModelIdentifier) { _, _ in coordinator.persistSchemePreferences() }
    }

    private var sourceAndTitle: (source: PhotoClassificationSourceScope, title: String)? {
        switch sourceMode {
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

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: task.state == .running ? "sparkles" : "photo.stack")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text(task.title)
                .font(.largeTitle.bold())
            ProgressView(
                value: Double(task.results.count),
                total: Double(max(task.assetFingerprints.count, 1))
            )
            .frame(maxWidth: 520)
            Text("已处理 \(task.results.count) / \(task.assetFingerprints.count) 张")
                .foregroundStyle(.secondary)

            HStack {
                if task.state == .running {
                    Button("暂停") { coordinator.pause(taskID: task.id) }
                } else {
                    Button(task.results.isEmpty ? "开始分类" : "继续分类") {
                        coordinator.startOrContinue(taskID: task.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(task.assetFingerprints.isEmpty)
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
    @State private var confirmingApply = false
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
                    Text("\(task.results.count) 张 · \(task.state.localizedTitle)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if task.state == .readyForReview {
                    Button("确认写入相册") { confirmingApply = true }
                        .buttonStyle(.borderedProminent)
                } else if task.state == .applying {
                    ProgressView().controlSize(.small)
                    Text("正在写入 Photos")
                } else if task.state == .applied {
                    Button("撤销本次整理") { confirmingUndo = true }
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                TargetAlbumMappingView(task: task, categories: categories)
                    .padding(20)

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
                        categories: categories,
                        selectedAssets: $selectedAssets,
                        inspectedResult: $inspectedResult
                    )
                }
                ClassificationGroupSection(
                    task: task,
                    categoryIdentifier: nil,
                    title: "待分类",
                    results: task.results.filter { $0.effectiveCategoryIdentifier == nil },
                    categories: categories,
                    selectedAssets: $selectedAssets,
                    inspectedResult: $inspectedResult
                )
            }
        }
        .sheet(item: $inspectedResult) { result in
            PhotoClassificationInspector(task: task, result: result, categories: categories)
                .environmentObject(coordinator)
        }
        .alert("确认写入 Apple Photos？", isPresented: $confirmingApply) {
            Button("取消", role: .cancel) {}
            Button("确认写入") { Task { await coordinator.apply(taskID: task.id) } }
        } message: {
            Text("只会创建或添加已确认的相册归属，不会删除照片或移除原有归属。")
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
                            Text("新建“\(category.category.name)”").tag(
                                PhotoAlbumTarget.newAlbum(name: category.category.name)
                            )
                            ForEach(coordinator.albums) { album in
                                Text("已有：\(album.name)").tag(
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
    let categories: [ReviewCategory]
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
                        PhotoClassificationCard(
                            task: task,
                            result: result,
                            categories: categories,
                            isSelected: selectedAssets.contains(result.id),
                            onToggleSelection: {
                                if selectedAssets.contains(result.id) {
                                    selectedAssets.remove(result.id)
                                } else {
                                    selectedAssets.insert(result.id)
                                }
                            },
                            onInspect: { inspectedResult = result }
                        )
                        .draggable(result.id)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .dropDestination(for: String.self) { identifiers, _ in
                for identifier in identifiers {
                    coordinator.updateCategory(
                        taskID: task.id,
                        assetIdentifier: identifier,
                        categoryIdentifier: categoryIdentifier
                    )
                }
                return true
            }
        }
    }
}

private struct PhotoClassificationCard: View {
    @EnvironmentObject private var coordinator: PhotoClassificationCoordinator
    let task: PhotoClassificationTask
    let result: PhotoClassificationResult
    let categories: [ReviewCategory]
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
                        .foregroundStyle(isSelected ? Color.white : Color.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            Text(result.reason)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Picker("分类", selection: Binding(
                get: { result.effectiveCategoryIdentifier },
                set: { coordinator.updateCategory(taskID: task.id, assetIdentifier: result.id, categoryIdentifier: $0) }
            )) {
                Text("待分类").tag(String?.none)
                ForEach(categories) { category in
                    Text(category.displayName).tag(Optional(category.id))
                }
            }
            .labelsHidden()
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
    let categories: [ReviewCategory]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("分类详情").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
            }
            AsyncPhotoThumbnail(assetIdentifier: result.id, longestEdge: 1200)
                .frame(maxWidth: 900, maxHeight: 600)
            Text(result.reason).foregroundStyle(.secondary)
            Picker("主分类", selection: Binding(
                get: { result.effectiveCategoryIdentifier },
                set: { coordinator.updateCategory(taskID: task.id, assetIdentifier: result.id, categoryIdentifier: $0) }
            )) {
                Text("待分类").tag(String?.none)
                ForEach(categories) { category in
                    Text(category.displayName).tag(Optional(category.id))
                }
            }
            .frame(maxWidth: 320)
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
        case .applied: "已整理"
        case .undone: "已撤销"
        case .failed: "失败"
        }
    }
}
