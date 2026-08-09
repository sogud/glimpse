//
//  SettingsView.swift
//  PhotoSwipeCleaner
//
//  精简设置页，只保留已接入主流程的配置
//

import SwiftUI
import Photos

/// 设置页面
struct SettingsView: View {
    @ObservedObject var viewModel: PhotoSwipeViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""

    @State private var showingRightAlbumPicker = false
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoSortAmbientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        settingsCardStack
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("偏好设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("重置确认", isPresented: $showingResetConfirmation) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    viewModel.resetAllSavedDecisions()
                    HapticService.shared.success()
                    NotificationCenter.default.post(name: .photosReset, object: nil)
                }
            } message: {
                Text("确定要重置所有整理决定吗？这将使 \(viewModel.savedDecisionCount) 张照片重新进入对应清理入口。")
            }
        }
    }

    @ViewBuilder
    private var settingsCardStack: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 22) {
                settingsCardStackContent
            }
        } else {
            settingsCardStackContent
        }
    }

    private var settingsCardStackContent: some View {
        VStack(spacing: 18) {
            deleteSafetySection
            archiveSection
            sessionSection
            onboardingSection
            aboutSection
        }
    }

    private var deleteSafetySection: some View {
        settingsSectionCard(
            title: "删除说明",
            footer: "先筛一轮，再统一确认删除。"
        ) {
            VStack(spacing: 14) {
                SettingRow(
                    icon: "tray.full.fill",
                    iconColor: .swipeDelete,
                    title: "左滑先加入待删除",
                    subtitle: "不是立即删除，整轮结束后再统一确认"
                )

                sectionDivider

                SettingRow(
                    icon: "trash",
                    iconColor: .labelOrange,
                    title: "只在最后触发一次系统弹窗",
                    subtitle: "批量删除后，照片会进入系统“最近删除”"
                )
            }
        }
    }

    private var archiveSection: some View {
        settingsSectionCard(
            title: "归档设置",
            footer: "设置后，右滑可以直接归档到这里。"
        ) {
            Button(action: { showingRightAlbumPicker = true }) {
                SettingRow(
                    icon: "folder.badge.plus",
                    iconColor: .swipeArchive,
                    title: "归档相册",
                    subtitle: swipeRightAlbum.isEmpty ? "未设置时右滑仅保留；归档模式开始前需先选择" : swipeRightAlbum,
                    showsChevron: true
                )
            }
            .buttonStyle(SubtleRowButtonStyle())
            .sheet(isPresented: $showingRightAlbumPicker) {
                AlbumSelectionSheet(
                    selectedAlbum: $swipeRightAlbum,
                    title: "选择归档相册",
                    emptySelectionTitle: "清空归档相册"
                )
            }
        }
    }

    private var sessionSection: some View {
        settingsSectionCard(
            title: "会话与数据",
            footer: "重置后，所有已处理记录都会重新出现。"
        ) {
            VStack(spacing: 14) {
                if let summary = viewModel.sessionSummary {
                    SettingRow(
                        icon: viewModel.activeWorkflow == .delete ? "trash.circle" : "folder",
                        iconColor: viewModel.activeWorkflow == .delete ? .swipeDelete : .swipeArchive,
                        title: viewModel.currentSessionTitle,
                        subtitle: "已处理 \(summary.processedCount)/\(summary.initialCount) 张"
                    )
                }

                if viewModel.hasPendingDeletionReview {
                    if viewModel.sessionSummary != nil {
                        sectionDivider
                    }

                    Button(action: {
                        viewModel.discardPendingDeletes()
                        dismiss()
                    }) {
                        SettingRow(
                            icon: "xmark.bin",
                            iconColor: .labelOrange,
                            title: "清空待删除清单",
                            subtitle: "撤回本轮已标记的待删除照片",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(SubtleRowButtonStyle())
                }

                if viewModel.sessionSummary != nil || viewModel.hasPendingDeletionReview {
                    sectionDivider
                }

                Button(action: {
                    showingResetConfirmation = true
                }) {
                    SettingRow(
                        icon: "arrow.counterclockwise",
                        iconColor: .labelOrange,
                        title: "重置已整理记录",
                        subtitle: "已记录 \(viewModel.savedDecisionCount) 个整理决定",
                        showsChevron: true
                    )
                }
                .buttonStyle(SubtleRowButtonStyle())
            }
        }
    }

    private var onboardingSection: some View {
        settingsSectionCard(title: "帮助") {
            Button(action: {
                onboardingManager.resetOnboarding()
                dismiss()
            }) {
                SettingRow(
                    icon: "book",
                    iconColor: .labelIndigo,
                    title: "重新显示新手引导",
                    subtitle: "再次查看删图、归档和权限说明",
                    showsChevron: true
                )
            }
            .buttonStyle(SubtleRowButtonStyle())
        }
    }

    private var aboutSection: some View {
        settingsSectionCard(title: "关于") {
            SettingRow(
                icon: "info.circle",
                iconColor: .labelGray,
                title: "版本",
                subtitle: nil,
                trailingText: appVersionText
            )
        }
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    private var sectionDivider: some View {
        Divider()
            .overlay(Color.white.opacity(0.08))
    }

    private func settingsSectionCard<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content()

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }
}

// MARK: - 设置行组件

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var trailingText: String? = nil
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if let trailingText {
                Text(trailingText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
}

// MARK: - 相册选择 Sheet

struct AlbumSelectionSheet: View {
    @Binding var selectedAlbum: String
    let title: String
    let emptySelectionTitle: String
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [PHAssetCollection] = []
    @State private var isLoading = true
    @State private var showingNewAlbumAlert = false
    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoSortAmbientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        selectionHeader
                        selectionCardStack
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
            }
            .alert("创建新相册", isPresented: $showingNewAlbumAlert) {
                TextField("相册名称", text: $newAlbumName)
                Button("创建") {
                    createNewAlbum()
                }
                Button("取消", role: .cancel) {
                    newAlbumName = ""
                }
            } message: {
                Text("请输入新相册的名称")
            }
        }
    }

    @ViewBuilder
    private var selectionCardStack: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 22) {
                selectionCardStackContent
            }
        } else {
            selectionCardStackContent
        }
    }

    private var selectionCardStackContent: some View {
        VStack(spacing: 18) {
            quickActionsCard
            existingAlbumsCard
        }
    }

    private var selectionHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary.opacity(0.14))
                    )

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(selectedAlbum.isEmpty ? "未设置" : selectedAlbum)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 28, tint: .white.opacity(0.1))
    }

    private var quickActionsCard: some View {
        AlbumPickerSectionCard(title: "快捷操作") {
            VStack(spacing: 14) {
                Button(action: clearSelection) {
                    AlbumPickerOptionRow(
                        icon: "slash.circle",
                        iconColor: .labelGray,
                        title: emptySelectionTitle,
                        subtitle: "清空后，右滑只保留，不自动归档。",
                        isSelected: selectedAlbum.isEmpty
                    )
                }
                .buttonStyle(SubtleRowButtonStyle())

                AlbumPickerDivider()

                Button(action: {
                    showingNewAlbumAlert = true
                }) {
                    AlbumPickerOptionRow(
                        icon: "plus.circle.fill",
                        iconColor: .brandPrimary,
                        title: "创建新相册",
                        subtitle: "现在只保存名称，第一次归档时会自动创建。",
                        showsChevron: true
                    )
                }
                .buttonStyle(SubtleRowButtonStyle())
            }
        }
    }

    private var existingAlbumsCard: some View {
        AlbumPickerSectionCard(
            title: "选择已有相册",
            footer: "选择默认归档相册后，删图流程里也可以顺手把值得保留的内容右滑收进去。"
        ) {
            if isLoading {
                AlbumPickerLoadingState(title: "加载相册中...")
            } else if albums.isEmpty {
                Text("还没有可选的用户相册")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(albums.enumerated()), id: \.element.localIdentifier) { index, album in
                    Button(action: {
                        selectedAlbum = album.localizedTitle ?? ""
                        dismiss()
                    }) {
                        VStack(spacing: 14) {
                            AlbumPickerOptionRow(
                                icon: "folder",
                                iconColor: .brandPrimary,
                                title: album.localizedTitle ?? "未知相册",
                                subtitle: "\(album.estimatedAssetCount) 张照片",
                                isSelected: selectedAlbum == album.localizedTitle
                            )

                            if index < albums.count - 1 {
                                AlbumPickerDivider()
                            }
                        }
                    }
                    .buttonStyle(SubtleRowButtonStyle())
                }
            }
        }
    }

    private func loadAlbums() {
        isLoading = true

        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        var loadedAlbums: [PHAssetCollection] = []
        userAlbums.enumerateObjects { collection, _, _ in
            if collection.localizedTitle != nil {
                loadedAlbums.append(collection)
            }
        }

        albums = loadedAlbums.sorted {
            ($0.localizedTitle ?? "") < ($1.localizedTitle ?? "")
        }
        isLoading = false
    }

    private func clearSelection() {
        selectedAlbum = ""
        dismiss()
    }

    private func createNewAlbum() {
        let trimmedName = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        selectedAlbum = trimmedName
        newAlbumName = ""
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    SettingsView(viewModel: PhotoSwipeViewModel())
        .environmentObject(OnboardingManager())
}
