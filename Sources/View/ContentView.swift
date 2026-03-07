//
//  ContentView.swift
//  PhotoSwipeCleaner
//
//  主应用入口视图 - 极简设计
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 主应用入口视图
struct ContentView: View {
    @StateObject private var viewModel = PhotoSwipeViewModel()
    @EnvironmentObject private var onboardingManager: OnboardingManager

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    // 状态管理
    @State private var showingPermissionAlert = false
    @State private var showingErrorAlert = false
    @State private var showingSettings = false
    @State private var showingAlbumSetup = false
    @State private var swipeInteractionProgress: CGFloat = 0

    // 用户设置
    @AppStorage("swipeLeftAlbum") private var swipeLeftAlbum: String = ""
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""
    @AppStorage("enableHardDelete") private var enableHardDelete = false
    @AppStorage("onboarding_completed") private var onboardingCompleted = false

    var body: some View {
        NavigationStack {
            ZStack {
                cameraBackground
                    .ignoresSafeArea()

                mainContent

                if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                    overlayChrome
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
            .sheet(isPresented: $viewModel.showSourceAlbumPicker) {
                SourceAlbumPickerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(onboardingManager)
            }
            .sheet(isPresented: $showingAlbumSetup) {
                AlbumSetupView()
            }
            .onAppear {
                refreshAuthorizationStatus()
                checkAlbumSetupNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                refreshAuthorizationStatus()
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
        }
    }

    // MARK: - Background

    private var cameraBackground: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.05, green: 0.09, blue: 0.13),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient.background
            }

            Circle()
                .fill(Color(red: 0.72, green: 0.89, blue: 1.0).opacity(colorScheme == .dark ? 0.12 : 0.3))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(x: -130, y: -220)

            Circle()
                .fill(Color(red: 0.72, green: 1.0, blue: 0.93).opacity(colorScheme == .dark ? 0.08 : 0.22))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 150, y: 260)
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

    private var currentPhotoDisplayIndex: Int {
        viewModel.allPhotos.isEmpty ? 0 : viewModel.currentIndex + 1
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

    // MARK: - Subviews

    // 顶部信息栏 - 胶片相机风格
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
        HStack {
            Button(action: { viewModel.showSourceAlbumPicker = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.selectedSourceAlbum ?? "所有照片")
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .adaptiveLiquidGlass(cornerRadius: 16, tint: .white.opacity(0.06), interactive: true)
            }
            .disabled(viewModel.isPerformingAction)

            Spacer(minLength: 10)

            HStack(spacing: 4) {
                Text(String(format: "%03d", currentPhotoDisplayIndex))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                Text("/")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.secondary)
                Text(String(format: "%03d", viewModel.allPhotos.count))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(colorScheme == .dark ? .white : .primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .adaptiveLiquidGlass(cornerRadius: 16, tint: .white.opacity(0.04))

            Spacer(minLength: 10)

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

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
            SwipeView(viewModel: viewModel, interactionProgress: $swipeInteractionProgress)
                .padding(.horizontal, 2)
                .padding(.top, 52)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            permissionRequestView
        }
    }

    private var permissionRequestView: some View {
        let isDenied = viewModel.authorizationStatus == .denied

        return VStack(spacing: 32) {
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
                Text(isDenied ? "请前往设置开启权限" : "需要相册权限")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(
                    isDenied
                        ? "您已拒绝相册访问权限。\n请在系统设置中允许访问后继续整理。"
                        : "为了帮您快速整理照片，\n我们需要访问您的相册。"
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
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(LinearGradient.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if isDenied {
                    Button("重新检查权限") {
                        refreshAuthorizationStatus()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 底部控制栏 - 胶片相机风格
    private var bottomControlBar: some View {
        let canSwipe = viewModel.currentPhoto != nil && !viewModel.isLoading && !viewModel.isPerformingAction
        let leftSwipeDeletes = enableHardDelete || swipeLeftAlbum.isEmpty

        return bottomControlBarContent(canSwipe: canSwipe, leftSwipeDeletes: leftSwipeDeletes)
            .padding(.horizontal, 18)
            .opacity(bottomChromeOpacity)
            .scaleEffect(bottomChromeScale, anchor: .bottom)
            .offset(y: bottomChromeOffset)
    }

    private func bottomControlBarContent(canSwipe: Bool, leftSwipeDeletes: Bool) -> some View {
        HStack(spacing: 24) {
            DockActionButton(
                icon: "xmark",
                iconColor: leftSwipeDeletes
                    ? Color(red: 0.84, green: 0.38, blue: 0.35)
                    : Color(red: 0.42, green: 0.56, blue: 0.72),
                albumName: leftSwipeDeletes ? "删除" : swipeLeftAlbum,
                isEnabled: canSwipe,
                action: { triggerSwipe(.left) }
            )

            Button(action: {
                viewModel.undoLastAction()
                HapticService.shared.medium()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill((viewModel.canUndo ? Color.primary : Color.secondary).opacity(colorScheme == .dark ? 0.14 : 0.08))
                        )

                    Text("撤销")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .foregroundColor(viewModel.canUndo
                                 ? (colorScheme == .dark ? .white : .primary)
                                 : .gray)
                .frame(width: 64)
            }
            .buttonStyle(.plain)
            .buttonStyle(DockPressButtonStyle())
            .disabled(!viewModel.canUndo || viewModel.isPerformingAction)

            DockActionButton(
                icon: "checkmark",
                iconColor: Color(red: 0.32, green: 0.66, blue: 0.52),
                albumName: swipeRightAlbum.isEmpty ? "保留" : swipeRightAlbum,
                isEnabled: canSwipe,
                action: { triggerSwipe(.right) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .adaptiveLiquidGlass(cornerRadius: 28, tint: .white.opacity(0.08))
        .floatingShadow(colorScheme: colorScheme)
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
            Task {
                do {
                    try await viewModel.loadPhotos()
                } catch {}
            }
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Action Button Component

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

                Text(albumName.isEmpty ? (icon == "xmark" ? "删除" : "保留") : albumName)
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
