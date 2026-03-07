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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @AppStorage("swipeLeftAlbum") private var swipeLeftAlbum: String = ""
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""
    @AppStorage("enableHardDelete") private var enableHardDelete = false

    @State private var showingLeftAlbumPicker = false
    @State private var showingRightAlbumPicker = false
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                albumSettingsSection
                resetSection
                onboardingSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
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
                    ProcessedPhotoManager.shared.resetAllProcessed()
                    HapticService.shared.success()
                    NotificationCenter.default.post(name: .photosReset, object: nil)
                }
            } message: {
                Text("确定要重置所有已整理记录吗？这将使 \(ProcessedPhotoManager.shared.processedCount) 张照片重新出现在主屏幕。")
            }
        }
    }

    private var albumSettingsSection: some View {
        Section {
            Button(action: { showingLeftAlbumPicker = true }) {
                SettingRow(
                    icon: "arrow.left",
                    iconColor: .swipeDelete,
                    title: "左滑目标相册",
                    subtitle: swipeLeftAlbum.isEmpty ? "未设置时左滑会删除" : swipeLeftAlbum
                )
            }
            .sheet(isPresented: $showingLeftAlbumPicker) {
                AlbumSelectionSheet(
                    selectedAlbum: $swipeLeftAlbum,
                    title: "选择左滑目标相册",
                    emptySelectionTitle: "不设置，保留删除行为"
                )
            }

            Button(action: { showingRightAlbumPicker = true }) {
                SettingRow(
                    icon: "arrow.right",
                    iconColor: .swipeKeep,
                    title: "右滑目标相册",
                    subtitle: swipeRightAlbum.isEmpty ? "未设置时右滑仅保留" : swipeRightAlbum
                )
            }
            .sheet(isPresented: $showingRightAlbumPicker) {
                AlbumSelectionSheet(
                    selectedAlbum: $swipeRightAlbum,
                    title: "选择右滑目标相册",
                    emptySelectionTitle: "不设置，保留当前保留行为"
                )
            }

            Toggle(isOn: $enableHardDelete) {
                SettingRow(
                    icon: "trash",
                    iconColor: .labelRed,
                    title: "彻底删除模式",
                    subtitle: enableHardDelete ? "即使设置了左滑相册，也优先执行删除" : "左滑优先移动到相册"
                )
            }
        } header: {
            Text("滑动行为")
        } footer: {
            Text("这个页面只保留真正影响主流程的配置。左滑默认删除，右滑默认保留；设置目标相册后，对应方向会改为移动到相册。")
        }
    }

    private var resetSection: some View {
        Section {
            Button(action: {
                showingResetConfirmation = true
            }) {
                SettingRow(
                    icon: "arrow.counterclockwise",
                    iconColor: .labelOrange,
                    title: "重置已整理记录",
                    subtitle: "已整理 \(ProcessedPhotoManager.shared.processedCount) 张照片"
                )
            }
        } header: {
            Text("数据管理")
        } footer: {
            Text("重置后，所有已整理过的照片会重新回到待处理列表。")
        }
    }

    private var onboardingSection: some View {
        Section {
            Button(action: {
                onboardingManager.resetOnboarding()
                dismiss()
            }) {
                SettingRow(
                    icon: "book",
                    iconColor: .labelIndigo,
                    title: "重新显示新手引导",
                    subtitle: "再次查看权限和相册设置说明"
                )
            }
        } header: {
            Text("帮助")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                SettingRow(
                    icon: "info.circle",
                    iconColor: .labelGray,
                    title: "版本",
                    subtitle: nil
                )

                Spacer()

                Text(appVersionText)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("关于")
        }
    }

    private var appVersionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }
}

// MARK: - 设置行组件

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

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
                }
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
            Group {
                if isLoading {
                    ProgressView("加载相册中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Button(action: clearSelection) {
                                HStack {
                                    Image(systemName: "slash.circle")
                                        .foregroundColor(.secondary)
                                    Text(emptySelectionTitle)
                                        .foregroundColor(.primary)
                                }
                            }
                        }

                        Section {
                            Button(action: {
                                showingNewAlbumAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.brandPrimary)
                                    Text("创建新相册")
                                        .foregroundColor(.primary)
                                }
                            }
                        }

                        Section("选择已有相册") {
                            ForEach(albums, id: \.localIdentifier) { album in
                                Button(action: {
                                    selectedAlbum = album.localizedTitle ?? ""
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                            .foregroundColor(.brandPrimary)
                                        Text(album.localizedTitle ?? "未知相册")
                                            .foregroundColor(.primary)

                                        Spacer()

                                        if selectedAlbum == album.localizedTitle {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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
    SettingsView()
        .environmentObject(OnboardingManager())
}
