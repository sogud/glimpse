//
//  SettingsView.swift
//  PhotoSwipeCleaner
//
//  设置页面
//

import SwiftUI
import Photos

/// 设置页面
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var onboardingManager: OnboardingManager
    
    // MARK: - AppStorage
    
    @AppStorage("autoSkipFavorites") private var autoSkipFavorites = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("hapticFeedback") private var hapticFeedbackEnabled = true
    @AppStorage("soundEffects") private var soundEffectsEnabled = false
    @AppStorage("swipeLeftAction") private var swipeLeftAction: SwipeAction = .delete
    @AppStorage("swipeRightAction") private var swipeRightAction: SwipeAction = .keep
    @AppStorage("swipeUpAction") private var swipeUpAction: SwipeAction = .moveToAlbum
    @AppStorage("swipeDownAction") private var swipeDownAction: SwipeAction = .skip
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system

    // 相册设置
    @AppStorage("swipeLeftAlbum") private var swipeLeftAlbum: String = ""
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""
    @AppStorage("enableHardDelete") private var enableHardDelete = false

    // 相册选择器状态
    @State private var showingLeftAlbumPicker = false
    @State private var showingRightAlbumPicker = false
    
    // 重置确认对话框
    @State private var showingResetConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                // 相册设置（核心功能）
                albumSettingsSection

                // 整理偏好
                preferencesSection

                // 手势自定义
                gestureSection

                // 外观设置
                appearanceSection

                // 数据管理
                resetSection

                // 引导与帮助
                helpSection

                // 关于
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
                    // 发送通知让主页刷新
                    NotificationCenter.default.post(name: .photosReset, object: nil)
                }
            } message: {
                Text("确定要重置所有已整理记录吗？这将使 \(ProcessedPhotoManager.shared.processedCount) 张照片重新出现在主屏幕。")
            }
        }
    }
    
    // MARK: - Sections
    
    private var preferencesSection: some View {
        Section {
            Toggle(isOn: $autoSkipFavorites) {
                SettingRow(
                    icon: "heart.fill",
                    iconColor: .labelRed,
                    title: "自动跳过收藏",
                    subtitle: "整理时跳过已收藏的照片"
                )
            }

            Toggle(isOn: $hapticFeedbackEnabled) {
                SettingRow(
                    icon: "hand.tap",
                    iconColor: .labelBlue,
                    title: "触觉反馈",
                    subtitle: "操作时提供震动反馈"
                )
            }

            Toggle(isOn: $soundEffectsEnabled) {
                SettingRow(
                    icon: "speaker.wave.2",
                    iconColor: .labelPurple,
                    title: "声音效果",
                    subtitle: "操作时播放音效"
                )
            }
        } header: {
            Text("整理偏好")
        } footer: {
            Text("这些设置会影响您在整理照片时的操作体验")
        }
    }

    private var albumSettingsSection: some View {
        Section {
            // 左滑相册选择
            Button(action: { showingLeftAlbumPicker = true }) {
                SettingRow(
                    icon: "arrow.left",
                    iconColor: .swipeDelete,
                    title: "左滑目标相册",
                    subtitle: swipeLeftAlbum.isEmpty ? "未设置" : swipeLeftAlbum
                )
            }
            .sheet(isPresented: $showingLeftAlbumPicker) {
                AlbumSelectionSheet(selectedAlbum: $swipeLeftAlbum, title: "选择左滑目标相册")
            }

            // 右滑相册选择
            Button(action: { showingRightAlbumPicker = true }) {
                SettingRow(
                    icon: "arrow.right",
                    iconColor: .swipeKeep,
                    title: "右滑目标相册",
                    subtitle: swipeRightAlbum.isEmpty ? "未设置" : swipeRightAlbum
                )
            }
            .sheet(isPresented: $showingRightAlbumPicker) {
                AlbumSelectionSheet(selectedAlbum: $swipeRightAlbum, title: "选择右滑目标相册")
            }

            // 彻底删除开关
            Toggle(isOn: $enableHardDelete) {
                SettingRow(
                    icon: "trash",
                    iconColor: .labelRed,
                    title: "彻底删除模式",
                    subtitle: enableHardDelete ? "左滑直接删除（会弹出系统确认）" : "左滑仅移动到相册"
                )
            }
        } header: {
            Text("相册设置")
        } footer: {
            Text("设置左右滑动对应的目标相册。开启彻底删除模式后，左滑将直接删除照片而非移动到相册。")
        }
    }
    
    private var gestureSection: some View {
        Section {
            NavigationLink {
                GestureCustomizationView(
                    title: "左滑操作",
                    action: $swipeLeftAction,
                    defaultColor: .swipeDelete
                )
            } label: {
                SettingRow(
                    icon: "arrow.left",
                    iconColor: .swipeDelete,
                    title: "左滑",
                    subtitle: swipeLeftAction.displayName
                )
            }

            NavigationLink {
                GestureCustomizationView(
                    title: "右滑操作",
                    action: $swipeRightAction,
                    defaultColor: .swipeKeep
                )
            } label: {
                SettingRow(
                    icon: "arrow.right",
                    iconColor: .swipeKeep,
                    title: "右滑",
                    subtitle: swipeRightAction.displayName
                )
            }
        } header: {
            Text("手势自定义")
        } footer: {
            Text("自定义左右滑动操作")
        }
    }
    
    private var appearanceSection: some View {
        Section {
            Picker("外观", selection: $themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("外观")
        } footer: {
            Text("选择应用的主题模式")
        }
    }
    
    private var helpSection: some View {
        Section {
            Button(action: {
                onboardingManager.resetOnboarding()
                dismiss()
            }) {
                SettingRow(
                    icon: "book",
                    iconColor: .labelIndigo,
                    title: "重新显示新手引导",
                    subtitle: nil
                )
            }
            
            Link(destination: URL(string: "https://www.apple.com")!) {
                SettingRow(
                    icon: "questionmark.circle",
                    iconColor: .labelTeal,
                    title: "帮助中心",
                    subtitle: nil
                )
            }
            
        } header: {
            Text("帮助")
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
            Text("重置后，所有已整理过的照片将重新出现在主屏幕")
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
                Text("1.1.0")
                    .foregroundColor(.secondary)
            }
            
            Link(destination: URL(string: "https://www.apple.com")!) {
                SettingRow(
                    icon: "doc.text",
                    iconColor: .labelGray,
                    title: "隐私政策",
                    subtitle: nil
                )
            }
            
            Link(destination: URL(string: "https://www.apple.com")!) {
                SettingRow(
                    icon: "checkmark.shield",
                    iconColor: .labelGray,
                    title: "使用条款",
                    subtitle: nil
                )
            }
        } header: {
            Text("关于")
        }
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
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - 手势自定义页面

struct GestureCustomizationView: View {
    let title: String
    @Binding var action: SwipeAction
    let defaultColor: Color
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                ForEach(SwipeAction.allCases) { swipeAction in
                    Button(action: {
                        action = swipeAction
                        HapticService.shared.selection()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: swipeAction.icon)
                                .foregroundColor(swipeAction.color)
                                .frame(width: 30)
                            
                            Text(swipeAction.displayName)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if action == swipeAction {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } header: {
                Text("选择操作")
            } footer: {
                Text("选择此方向滑动手势对应的操作")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 数据模型

/// 滑动操作选项
enum SwipeAction: String, CaseIterable, Identifiable {
    case delete = "delete"
    case keep = "keep"
    case moveToAlbum = "moveToAlbum"
    case skip = "skip"
    case favorite = "favorite"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .delete:
            return "删除"
        case .keep:
            return "保留"
        case .moveToAlbum:
            return "移动到相册"
        case .skip:
            return "跳过"
        case .favorite:
            return "收藏"
        }
    }
    
    var icon: String {
        switch self {
        case .delete:
            return "trash"
        case .keep:
            return "checkmark"
        case .moveToAlbum:
            return "folder"
        case .skip:
            return "clock"
        case .favorite:
            return "heart"
        }
    }
    
    var color: Color {
        switch self {
        case .delete:
            return .swipeDelete
        case .keep:
            return .swipeKeep
        case .moveToAlbum:
            return .swipeArchive
        case .skip:
            return .swipeSkip
        case .favorite:
            return .labelRed
        }
    }
}

/// 主题模式
enum ThemeMode: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case system = "system"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        case .system:
            return "自动"
        }
    }
}

// MARK: - 相册选择 Sheet

struct AlbumSelectionSheet: View {
    @Binding var selectedAlbum: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [PHAssetCollection] = []
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("加载相册中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // 创建新相册选项
                        Button(action: {
                            createNewAlbum()
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.brandPrimary)
                                Text("创建新相册")
                                    .foregroundColor(.primary)
                            }
                        }

                        // 现有相册列表
                        Section(header: Text("选择已有相册")) {
                            ForEach(albums, id: \.localIdentifier) { album in
                                Button(action: {
                                    selectedAlbum = album.localizedTitle ?? "未知相册"
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
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
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

        albums = loadedAlbums
        isLoading = false
    }

    private func createNewAlbum() {
        let alert = UIAlertController(
            title: "创建新相册",
            message: "请输入相册名称",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "相册名称"
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { _ in
            if let name = alert.textFields?.first?.text, !name.isEmpty {
                selectedAlbum = name
                dismiss()
            }
        })

        // 获取当前窗口并显示
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environmentObject(OnboardingManager())
}
