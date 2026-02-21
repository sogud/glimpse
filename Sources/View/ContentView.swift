//
//  ContentView.swift
//  PhotoSwipeCleaner
//
//  主应用入口视图 - 极简设计
//

import SwiftUI

/// 主应用入口视图
struct ContentView: View {
    @StateObject private var viewModel = PhotoSwipeViewModel()
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @Environment(\.colorScheme) private var colorScheme

    // 状态管理
    @State private var showingPermissionAlert = false
    @State private var showingAlbumPicker = false
    @State private var showingErrorAlert = false
    @State private var showingSettings = false
    @State private var showingHelp = false
    @State private var showingAlbumSetup = false

    // 用户设置
    @AppStorage("swipeLeftAlbum") private var swipeLeftAlbum: String = ""
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""
    @AppStorage("enableHardDelete") private var enableHardDelete = false
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 胶片相机风格背景 - 根据亮暗模式适配
                cameraBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部：照片信息栏（胶片风格）
                    if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                        topInfoBar
                    }

                    // 主要的滑动区域
                    mainContent

                    // 底部：胶片相机风格控制栏
                    if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                        bottomControlBar
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .alert("权限请求", isPresented: $showingPermissionAlert) {
                Button("授予权限") {
                    Task {
                        await viewModel.requestPermission()
                    }
                }
                Button("稍后再说", role: .cancel) {}
            } message: {
                Text("需要访问您的相册来整理照片。请授予权限以继续。")
            }
            .alert("错误", isPresented: $showingErrorAlert) {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "发生未知错误")
            }
            .sheet(isPresented: $showingAlbumPicker) {
                AlbumPickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showSourceAlbumPicker) {
                SourceAlbumPickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(onboardingManager)
            }
            .sheet(isPresented: $showingHelp) {
                HelpSheet()
            }
            .sheet(isPresented: $showingAlbumSetup) {
                AlbumSetupView()
            }
            .onAppear {
                handleAuthorizationStatus()
                checkAlbumSetupNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .photosReset)) { _ in
                Task {
                    do {
                        try await viewModel.loadPhotos()
                    } catch {}
                }
            }
            .onChange(of: viewModel.errorMessage) {
                if viewModel.errorMessage != nil {
                    showingErrorAlert = true
                }
            }
            .onChange(of: viewModel.showAlbumPicker) {
                if viewModel.showAlbumPicker {
                    showingAlbumPicker = true
                    viewModel.showAlbumPicker = false
                }
            }
        }
    }

    // MARK: - Background

    private var cameraBackground: some View {
        Group {
            if colorScheme == .dark {
                // 暗模式：纯黑
                Color.black
            } else {
                // 亮模式：米白色（类似拍立得背景）
                Color(red: 0.95, green: 0.95, blue: 0.93)
            }
        }
    }

    // MARK: - Subviews

    // 顶部信息栏 - 胶片相机风格
    private var topInfoBar: some View {
        HStack {
            // 相册选择按钮
            Button(action: { viewModel.showSourceAlbumPicker = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .medium))
                    Text(viewModel.selectedSourceAlbum ?? "所有照片")
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
            }

            Spacer()

            // 计数器 - 胶片风格（如 1/100）
            HStack(spacing: 4) {
                Text(String(format: "%03d", viewModel.currentIndex + 1))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text("/")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .gray : .secondary)

                Text(String(format: "%03d", viewModel.allPhotos.count))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(colorScheme == .dark ? .gray : .secondary)
            }

            Spacer()

            // 设置按钮 - 简化
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black : Color(red: 0.95, green: 0.95, blue: 0.93))
    }

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
            SwipeView(viewModel: viewModel)
                .padding(.horizontal, 20)
        } else {
            permissionRequestView
        }
    }

    private var permissionRequestView: some View {
        VStack(spacing: 32) {
            Spacer()

            // 图标
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.brandPrimary)
            }

            VStack(spacing: 12) {
                Text("需要相册权限")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("为了帮您快速整理照片，\n我们需要访问您的相册。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }

            Spacer()

            // 授予权限按钮
            Button(action: { showingPermissionAlert = true }) {
                HStack(spacing: 8) {
                    Text("授予权限")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient.brand
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 底部控制栏 - 胶片相机风格
    private var bottomControlBar: some View {
        HStack(spacing: 60) {
            // 左滑按钮（删除/移动到相册A）
            ActionButton(
                icon: "xmark",
                iconColor: enableHardDelete ? .swipeDelete : .swipeArchive,
                albumName: enableHardDelete ? "删除" : swipeLeftAlbum,
                action: { triggerSwipe(.left) }
            )

            // 撤销按钮（中间）
            Button(action: {
                viewModel.undoLastAction()
                HapticService.shared.medium()
            }) {
                ZStack {
                    Circle()
                        .fill(viewModel.canUndo
                              ? (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                              : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)))
                        .frame(width: 56, height: 56)

                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(viewModel.canUndo
                                         ? (colorScheme == .dark ? .white : .primary)
                                         : .gray)
                }
            }
            .disabled(!viewModel.canUndo)

            // 右滑按钮（保留/移动到相册B）
            ActionButton(
                icon: "checkmark",
                iconColor: .swipeKeep,
                albumName: swipeRightAlbum.isEmpty ? "保留" : swipeRightAlbum,
                action: { triggerSwipe(.right) }
            )
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: colorScheme == .dark ?
                    [Color.black.opacity(0), Color.black.opacity(0.8), Color.black] :
                    [Color(red: 0.95, green: 0.95, blue: 0.93).opacity(0), Color(red: 0.95, green: 0.95, blue: 0.93).opacity(0.8), Color(red: 0.95, green: 0.95, blue: 0.93)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func triggerSwipe(_ direction: GestureDirection) {
        // 触发通知让 SwipeView 处理滑动
        NotificationCenter.default.post(name: .triggerSwipe, object: direction)
    }

    private func checkAlbumSetupNeeded() {
        // 如果已完成引导但尚未设置相册，显示设置页面
        if onboardingCompleted && swipeLeftAlbum.isEmpty && swipeRightAlbum.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingAlbumSetup = true
            }
        }
    }

    private func handleAuthorizationStatus() {
        switch viewModel.authorizationStatus {
        case .notDetermined:
            showingPermissionAlert = true
        case .denied:
            break
        case .authorized, .limited:
            Task {
                do {
                    try await viewModel.loadPhotos()
                } catch {}
            }
        @unknown default:
            break
        }
    }
}

// MARK: - Help Sheet

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // 标题
                VStack(spacing: 8) {
                    Text("手势操作")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("像刷卡片一样整理照片")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // 操作说明
                VStack(spacing: 20) {
                    helpItem(
                        icon: "arrow.left",
                        title: "左滑",
                        description: "移动到左滑目标相册",
                        color: .swipeDelete
                    )

                    helpItem(
                        icon: "arrow.right",
                        title: "右滑",
                        description: "移动到右滑目标相册",
                        color: .swipeKeep
                    )
                }
                .padding(.horizontal, 24)

                // 提示
                VStack(spacing: 12) {
                    Label("所有操作可撤销", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Label("点击底部撤销按钮回退", systemImage: "hand.tap")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                Spacer()

                // 完成按钮
                Button(action: { dismiss() }) {
                    Text("知道了")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient.brand
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }

    private func helpItem(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Action Button Component

struct ActionButton: View {
    let icon: String
    let iconColor: Color
    let albumName: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // 外圈光晕
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 72, height: 72)
                        .blur(radius: 8)

                    // 主按钮
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(iconColor.opacity(0.5), lineWidth: 2)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(iconColor)
                }

                // 相册名称
                Text(albumName.isEmpty ? (icon == "xmark" ? "删除" : "保留") : albumName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let triggerSwipe = Notification.Name("triggerSwipe")
    static let photosReset = Notification.Name("photosReset")
}

// MARK: - Preview
#Preview("Light Mode") {
    ContentView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    ContentView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
