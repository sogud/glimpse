//
//  ContentView.swift
//  PhotoSwipeCleaner
//
//  删图主流程入口
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 主应用入口视图
struct ContentView: View {
    @StateObject private var viewModel: PhotoSwipeViewModel
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingPermissionAlert = false
    @State private var showingErrorAlert = false
    @State private var showingSettings = false
    @State private var showingSourceAlbumPicker = false
    @State private var showingArchiveAlbumPicker = false
    @State private var swipeInteractionProgress: CGFloat = 0
    @State private var selectedWorkflow: CleanupWorkflow = .delete
    @State private var showingHomeWhileSessionActive = false
    @State private var showingDeleteToast = false
    @State private var deleteToastMessage = ""

    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: PhotoSwipeViewModel())
    }

    @MainActor
    init(viewModel: PhotoSwipeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                cameraBackground
                    .ignoresSafeArea()

                mainContent

                if isImmersiveSwipeSession {
                    overlayChrome
                }

                if showingDeleteToast {
                    deleteToastView
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(isImmersiveSwipeSession ? .hidden : .visible, for: .tabBar)
            .alert("权限请求", isPresented: $showingPermissionAlert) {
                Button("授予权限") {
                    Task {
                        await viewModel.requestPermission()
                    }
                }
                Button("稍后再说", role: .cancel) {}
            } message: {
                Text("为了从候选照片中快速删除不需要的内容，我们需要访问你的相册。")
            }
            .alert("错误", isPresented: $showingErrorAlert) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "发生未知错误")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(viewModel: viewModel)
                    .environmentObject(onboardingManager)
            }
            .sheet(isPresented: $showingSourceAlbumPicker) {
                SourceAlbumPickerView(
                    viewModel: viewModel,
                    workflow: viewModel.activeWorkflow ?? selectedWorkflow,
                    targetAlbum: currentArchiveAlbum
                )
            }
            .sheet(isPresented: $showingArchiveAlbumPicker) {
                AlbumSelectionSheet(
                    selectedAlbum: $swipeRightAlbum,
                    title: "选择归档相册",
                    emptySelectionTitle: "清空归档相册"
                )
            }
            .onAppear {
                refreshAuthorizationStatus()
                Task {
                    await viewModel.resumeCurrentSessionIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                refreshAuthorizationStatus()
                Task {
                    await viewModel.resumeCurrentSessionIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .photosReset)) { _ in
                Task {
                    await viewModel.reloadCurrentSession()
                }
            }
            .onChange(of: viewModel.errorMessage) {
                if viewModel.errorMessage != nil {
                    showingErrorAlert = true
                }
            }
            .onChange(of: viewModel.hasActiveSession) { _, hasActiveSession in
                if !hasActiveSession {
                    showingHomeWhileSessionActive = false
                }
            }
        }
    }

    private var isAuthorized: Bool {
        viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited
    }

    private var isImmersiveSwipeSession: Bool {
        viewModel.hasActiveSession && !viewModel.isSessionComplete && !showingHomeWhileSessionActive && isAuthorized
    }

    private var currentSessionProgress: String {
        guard let summary = viewModel.sessionSummary else { return "0/0" }
        return summary.progressText
    }

    private var currentArchiveAlbum: String? {
        let sessionAlbum = viewModel.selectedTargetAlbum?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sessionAlbum, !sessionAlbum.isEmpty {
            return sessionAlbum
        }

        let trimmed = swipeRightAlbum.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canStartOrganizeSession: Bool {
        currentArchiveAlbum != nil
    }

    private var hasPausedSession: Bool {
        viewModel.hasActiveSession && !viewModel.isSessionComplete && showingHomeWhileSessionActive
    }

    private var topChromeOpacity: Double {
        1 - Double(min(swipeInteractionProgress, 1)) * 0.18
    }

    private var topChromeScale: CGFloat {
        1 - (min(swipeInteractionProgress, 1) * 0.02)
    }

    private var topChromeOffset: CGFloat {
        -min(swipeInteractionProgress, 1) * 6
    }

    private var bottomChromeOpacity: Double {
        1 - Double(min(swipeInteractionProgress, 1)) * 0.28
    }

    private var bottomChromeScale: CGFloat {
        1 - (min(swipeInteractionProgress, 1) * 0.03)
    }

    private var bottomChromeOffset: CGFloat {
        min(swipeInteractionProgress, 1) * 8
    }

    // MARK: - Background

    private var cameraBackground: some View {
        PhotoSortAmbientBackground()
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if isAuthorized {
            if viewModel.isSessionComplete {
                sessionSummaryView
            } else if viewModel.hasActiveSession && !showingHomeWhileSessionActive {
                SwipeView(viewModel: viewModel, interactionProgress: $swipeInteractionProgress)
                    .padding(.horizontal, 2)
                    .padding(.top, 52)
                    .padding(.bottom, 76)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cleanupEntryView
            }
        } else {
            permissionRequestView
        }
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            topInfoBar
            Spacer(minLength: 0)
            bottomControlBar
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: swipeInteractionProgress)
    }

    private var topInfoBar: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    topInfoBarContent
                }
            } else {
                topInfoBarContent
            }
        }
        .padding(.horizontal, 16)
        .opacity(topChromeOpacity)
        .scaleEffect(topChromeScale, anchor: .top)
        .offset(y: topChromeOffset)
    }

    private var topInfoBarContent: some View {
        HStack(spacing: 10) {
            homeButton

            sessionLeadingChip

            if viewModel.activeWorkflow == .delete && viewModel.pendingDeleteCount > 0 {
                Button(action: {
                    let pendingCount = viewModel.pendingDeleteCount
                    Task {
                        await viewModel.commitPendingDeletes()
                        if pendingCount > 0 && viewModel.pendingDeleteCount == 0 {
                            showDeleteToast("已删除 \(pendingCount) 张")
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("确认删除 \(viewModel.pendingDeleteCount)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.swipeDelete)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isPerformingAction)
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(currentSessionProgress)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(colorScheme == .dark ? .white : .primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .adaptiveLiquidGlass(cornerRadius: 16, tint: .white.opacity(0.04))

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .frame(width: 40, height: 40)
                    .adaptiveLiquidGlass(cornerRadius: 20, tint: .white.opacity(0.06), interactive: true)
            }
            .disabled(viewModel.isPerformingAction)
        }
    }

    private var homeButton: some View {
        Button(action: { showingHomeWhileSessionActive = true }) {
            Image(systemName: "house.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .frame(width: 40, height: 40)
                .adaptiveLiquidGlass(cornerRadius: 20, tint: .white.opacity(0.06), interactive: true)
        }
        .disabled(viewModel.isPerformingAction)
    }

    @ViewBuilder
    private var sessionLeadingChip: some View {
        if viewModel.activePreset == .advancedAlbum {
            Button(action: { showingSourceAlbumPicker = true }) {
                chipLabel(title: viewModel.currentSessionTitle, subtitle: viewModel.currentSessionChipSubtitle)
                    .adaptiveLiquidGlass(cornerRadius: 16, tint: .white.opacity(0.06), interactive: true)
            }
            .disabled(viewModel.isPerformingAction)
        } else {
            chipLabel(title: viewModel.currentSessionTitle, subtitle: viewModel.currentSessionChipSubtitle)
                .adaptiveLiquidGlass(cornerRadius: 16, tint: .white.opacity(0.06))
        }
    }

    private func chipLabel(title: String, subtitle: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))

                if !subtitle.isEmpty {
                    Text("·")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .foregroundStyle(colorScheme == .dark ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Entry View

    private var cleanupEntryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if hasPausedSession {
                    pausedSessionCard
                }

                workflowPicker
                entryHeader
                entrySurfaceStack
                .disabled(hasPausedSession)
                .opacity(hasPausedSession ? 0.45 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var entrySurfaceStack: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 24) {
                entrySurfaceStackContent
            }
        } else {
            entrySurfaceStackContent
        }
    }

    private var entrySurfaceStackContent: some View {
        VStack(spacing: 14) {
            if selectedWorkflow == .organize {
                sessionSetupCard
            }

            VStack(spacing: 14) {
                ForEach([CleanupPreset.screenshots, .videos, .recentThirtyDays], id: \.id) { preset in
                    presetCard(preset)
                }
            }
        }
    }

    private var pausedSessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("上次会话还在")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("你已经开始了 \(viewModel.currentSessionTitle)。可以继续处理，也可以结束本轮后重新开始。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }
            }

            HStack(spacing: 10) {
                Button("继续上次") {
                    showingHomeWhileSessionActive = false
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .adaptiveGlassProminentButton(cornerRadius: 16, expands: true)

                Button("结束本轮") {
                    viewModel.resetForNewSession()
                    showingHomeWhileSessionActive = false
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .adaptiveGlassButton(cornerRadius: 16, tint: .white.opacity(0.08), expands: true)
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.1))
    }

    private var workflowPicker: some View {
        HStack(spacing: 10) {
            ForEach(CleanupWorkflow.allCases) { workflow in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedWorkflow = workflow
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: workflow == .delete ? "trash.fill" : "folder.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text(workflow.title)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(selectedWorkflow == workflow ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(workflowBackground(for: workflow))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.08))
    }

    @ViewBuilder
    private func workflowBackground(for workflow: CleanupWorkflow) -> some View {
        if selectedWorkflow == workflow {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient.brand)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.12))
        }
    }

    private var entryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedWorkflow.entryTitle)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
    }

    private func presetCard(_ preset: CleanupPreset) -> some View {
        Button {
            Task {
                await viewModel.startSession(
                    workflow: selectedWorkflow,
                    preset: preset,
                    targetAlbum: currentArchiveAlbum
                )
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient.brand)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(preset.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(preset.description(for: selectedWorkflow))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(18)
            .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.1), interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(selectedWorkflow == .organize && !canStartOrganizeSession)
        .opacity(selectedWorkflow == .organize && !canStartOrganizeSession ? 0.55 : 1)
    }

    private var sessionSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("归档相册")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Button(action: { showingArchiveAlbumPicker = true }) {
                sessionSetupRow(
                    value: currentArchiveAlbum ?? "未选择",
                    icon: "folder.badge.plus",
                    accent: currentArchiveAlbum == nil ? .secondary : .swipeArchive
                )
            }
            .buttonStyle(SubtleRowButtonStyle())
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.08))
    }

    private func sessionSetupRow(value: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                )

            Text(value)
                .font(.body.weight(.medium))
                .foregroundColor(currentArchiveAlbum == nil ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    // MARK: - Completion View

    private var sessionSummaryView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: summaryIconName)
                .font(.system(size: 72, weight: .medium))
                .foregroundColor(summaryIconColor)

            VStack(spacing: 10) {
                Text(summaryHeadline)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(summaryDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }

            sessionSummarySurfaceGroup
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var sessionSummarySurfaceGroup: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                sessionSummarySurfaceGroupContent
            }
        } else {
            sessionSummarySurfaceGroupContent
        }
    }

    private var sessionSummarySurfaceGroupContent: some View {
        VStack(spacing: 12) {
            if let summary = viewModel.sessionSummary {
                VStack(spacing: 12) {
                    summaryRow(title: "候选总数", value: "\(summary.initialCount) 张")
                    if summary.workflow == .delete {
                        summaryRow(
                            title: "已标记删除",
                            value: "\(summary.markedDeleteCount) 张"
                        )
                        if viewModel.pendingDeleteCount > 0 {
                            summaryRow(title: "预计释放", value: summary.estimatedDeletedSizeText)
                        }
                        summaryRow(title: summary.movedCount > 0 ? "保留 / 归档" : "已保留", value: "\(summary.keptCount + summary.movedCount) 张")
                    } else {
                        summaryRow(title: "已归档", value: "\(summary.movedCount) 张")
                        summaryRow(title: "暂不处理", value: "\(summary.keptCount) 张")
                        summaryRow(title: "目标相册", value: summary.targetAlbumName ?? "未设置")
                    }
                }
                .padding(18)
                .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
            }

            VStack(spacing: 12) {
                if viewModel.hasPendingDeletionReview {
                    Button("一键删除 \(viewModel.pendingDeleteCount) 张") {
                        Task {
                            await viewModel.commitPendingDeletes()
                        }
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .adaptiveGlassProminentButton(cornerRadius: 18, expands: true)

                    Button("清空待删除清单") {
                        viewModel.discardPendingDeletes()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .adaptiveGlassButton(cornerRadius: 18, tint: .white.opacity(0.08), expands: true)
                    .disabled(viewModel.isPerformingAction)
                } else {
                    Button("开始下一次处理") {
                        viewModel.resetForNewSession()
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .adaptiveGlassProminentButton(cornerRadius: 18, expands: true)

                    Button("查看设置") {
                        showingSettings = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .adaptiveGlassButton(cornerRadius: 18, tint: .white.opacity(0.08), expands: true)
                }
            }
        }
    }

    private var summaryHeadline: String {
        guard let summary = viewModel.sessionSummary else {
            return "这轮处理完成了"
        }

        switch summary.workflow {
        case .delete:
            return summary.hasCommittedPendingDeletes ? "这批照片已经交给系统删除" : "先筛完，再一次性删除"
        case .organize:
            return "这批照片已经整理进相册"
        }
    }

    private var summaryDescription: String {
        guard let summary = viewModel.sessionSummary else {
            return "本轮已经结束。"
        }

        switch summary.workflow {
        case .delete:
            if summary.hasCommittedPendingDeletes {
                return "你刚完成了 \(viewModel.currentSessionTitle)，系统会把这批照片放进“最近删除”，仍可在系统相册中恢复。"
            }
            return "你已经标记了 \(summary.markedDeleteCount) 张删除候选。点一次“一键删除全部”后，系统只会弹出一次确认。"
        case .organize:
            let target = summary.targetAlbumName ?? "目标相册"
            return "你刚完成了 \(viewModel.currentSessionTitle)，其中选中的照片已经直接加入 \(target)。"
        }
    }

    private var summaryIconName: String {
        guard let summary = viewModel.sessionSummary else {
            return "checkmark.circle.fill"
        }

        switch summary.workflow {
        case .delete:
            return summary.hasCommittedPendingDeletes ? "trash.circle.fill" : "tray.full.fill"
        case .organize:
            return "folder.badge.plus"
        }
    }

    private var summaryIconColor: Color {
        guard let summary = viewModel.sessionSummary else {
            return .swipeKeep
        }

        switch summary.workflow {
        case .delete:
            return summary.hasCommittedPendingDeletes ? .swipeDelete : .brandPrimary
        case .organize:
            return .swipeArchive
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .font(.subheadline)
    }

    // MARK: - Permission

    private var permissionRequestView: some View {
        let isDenied = viewModel.authorizationStatus == .denied

        return VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: "trash.circle")
                    .font(.system(size: 54, weight: .light))
                    .foregroundColor(.brandPrimary)
            }

            VStack(spacing: 12) {
                Text(isDenied ? "请前往设置开启权限" : "需要相册权限")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(
                    isDenied
                        ? "开启权限后，你就可以从截图、视频或最近照片中快速筛掉不需要的内容，也能顺手把值得保留的照片归档。"
                        : "PhotoSort 会在本地帮你筛出候选照片。待删除内容会先进入清单，你可以随时在顶部确认删除。"
                )
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    if isDenied {
                        openAppSettings()
                    } else {
                        showingPermissionAlert = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Text(isDenied ? "打开设置" : "授予权限")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Image(systemName: isDenied ? "gearshape.fill" : "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .adaptiveGlassProminentButton(cornerRadius: 16, expands: true)

                if isDenied {
                    Button("重新检查权限") {
                        refreshAuthorizationStatus()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .adaptiveGlassButton(cornerRadius: 16, tint: .white.opacity(0.08), expands: true)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomControlBar: some View {
        let canSwipe = viewModel.currentPhoto != nil && !viewModel.isLoading && !viewModel.isPerformingAction
        let isDeleteWorkflow = viewModel.activeWorkflow == .delete
        let rightActionTitle = currentArchiveAlbum ?? "保留"
        let rightActionColor: Color = (viewModel.activeWorkflow == .organize || currentArchiveAlbum != nil) ? .swipeArchive : .swipeKeep
        let rightActionIcon = (viewModel.activeWorkflow == .organize || currentArchiveAlbum != nil) ? "folder.badge.plus" : "checkmark"

        return HStack(spacing: 18) {
            DockActionButton(
                icon: isDeleteWorkflow ? "trash" : "arrow.left",
                iconColor: isDeleteWorkflow ? .swipeDelete : .swipeSkip,
                albumName: isDeleteWorkflow ? "待删除" : "跳过",
                isEnabled: canSwipe,
                action: { triggerSwipe(.left) }
            )

            HStack(spacing: 8) {
                Button(action: {
                    viewModel.undoLastAction()
                    HapticService.shared.medium()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill((viewModel.canUndo ? Color.primary : Color.secondary).opacity(colorScheme == .dark ? 0.14 : 0.08))
                        )

                        .foregroundColor(viewModel.canUndo ? (colorScheme == .dark ? .white : .primary) : .gray)
                }
                .buttonStyle(.plain)
                .buttonStyle(DockPressButtonStyle())
                .disabled(!viewModel.canUndo || viewModel.isPerformingAction)
                .accessibilityLabel("撤销")

                Button(action: {
                    viewModel.reviewCurrentPhotoLater()
                    HapticService.shared.light()
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(Color.swipeSkip.opacity(colorScheme == .dark ? 0.18 : 0.1))
                        )
                        .foregroundColor(.swipeSkip)
                }
                .buttonStyle(.plain)
                .buttonStyle(DockPressButtonStyle())
                .disabled(!canSwipe)
                .accessibilityLabel("30 天后再看")
            }

            DockActionButton(
                icon: rightActionIcon,
                iconColor: rightActionColor,
                albumName: rightActionTitle,
                isEnabled: canSwipe,
                action: { triggerSwipe(.right) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .adaptiveLiquidGlass(cornerRadius: 28, tint: .white.opacity(0.08))
        .floatingShadow(colorScheme: colorScheme)
        .padding(.horizontal, 18)
        .opacity(bottomChromeOpacity)
        .scaleEffect(bottomChromeScale, anchor: .bottom)
        .offset(y: bottomChromeOffset)
    }

    // MARK: - Actions

    private func triggerSwipe(_ direction: GestureDirection) {
        NotificationCenter.default.post(name: .triggerSwipe, object: direction)
    }

    private func refreshAuthorizationStatus() {
        viewModel.checkAuthorizationStatus()
        handleAuthorizationStatus()
    }

    private func handleAuthorizationStatus() {
        switch viewModel.authorizationStatus {
        case .notDetermined:
            showingPermissionAlert = true
        case .denied:
            break
        case .authorized, .limited:
            break
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private var deleteToastView: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(deleteToastMessage)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

            Spacer()
        }
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: showingDeleteToast)
    }

    private func showDeleteToast(_ message: String) {
        deleteToastMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showingDeleteToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                showingDeleteToast = false
            }
        }
    }
}

struct DockActionButton: View {
    let icon: String
    let iconColor: Color
    let albumName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(iconColor.opacity(isEnabled ? 0.14 : 0.07))
                    )

                Text(albumName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 68)
            }
            .frame(width: 68)
            .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .buttonStyle(DockPressButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct DockPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension Notification.Name {
    static let triggerSwipe = Notification.Name("triggerSwipe")
    static let photosReset = Notification.Name("photosReset")
}

#Preview("Light Mode") {
    ContentView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    ContentView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
