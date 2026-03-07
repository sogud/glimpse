//
//  PermissionRequestView.swift
//  PhotoSwipeCleaner
//
//  权限申请页面 - 玻璃拟态设计
//

import SwiftUI
import Photos
#if canImport(UIKit)
import UIKit
#endif

/// 权限申请页面
struct OnboardingPermissionRequestView: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 权限图标动画
            permissionAnimation

            Spacer()

            // 说明文字
            contentSection

            Spacer()

            // 底部按钮
            bottomSection
        }
        .padding()
        .onAppear {
            checkCurrentStatus()
        }
    }

    // MARK: - Subviews

    private var permissionAnimation: some View {
        ZStack {
            // 背景圆环 - 柔和版
            Circle()
                .stroke(Color.brandPrimary.opacity(0.08), lineWidth: 1.5)
                .frame(width: 220, height: 220)

            // 脉冲动画 - 柔和
            PulseAnimation()

            // 主图标 - 玻璃拟态风格
            ZStack {
                Circle()
                    .fill(LinearGradient.brand)
                    .frame(width: 140, height: 140)
                    .floatingShadow(colorScheme: colorScheme)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(.white)
            }

            // 小锁图标
            Image(systemName: "lock.open.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.swipeKeep)
                        .shadow(color: Color.swipeKeep.opacity(0.3), radius: 8, x: 0, y: 4)
                )
                .offset(x: 50, y: 50)
        }
        .frame(height: 300)
    }

    private var contentSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("需要相册权限")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("为了帮您快速整理照片，我们需要访问您的相册")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // 权限说明列表 - 玻璃拟态卡片
            VStack(alignment: .leading, spacing: 16) {
                permissionItem(
                    icon: "photo",
                    title: "读取照片",
                    description: "用于展示和整理您的照片"
                )

                permissionItem(
                    icon: "trash",
                    title: "删除照片",
                    description: "帮您删除不需要的照片"
                )

                permissionItem(
                    icon: "folder",
                    title: "管理相册",
                    description: "将照片移动到指定相册"
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal)
        }
    }

    private func permissionItem(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.brandPrimary)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.brandPrimary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 16) {
            // 根据权限状态显示不同按钮
            switch authorizationStatus {
            case .notDetermined:
                requestButton

            case .authorized, .limited:
                continueButton

            case .denied, .restricted:
                goToSettingsButton

            @unknown default:
                requestButton
            }

            // 隐私承诺
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                Text("您的照片始终在本地处理，绝不会上传")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
            )

            // 页码指示器
            PageIndicator(currentPage: 2, totalPages: OnboardingStep.allCases.count)
        }
        .padding(.bottom, 20)
    }

    private var requestButton: some View {
        Button(action: requestPermission) {
            HStack(spacing: 8) {
                if isRequesting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text("授予权限")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(LinearGradient.brand)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .floatingShadow(colorScheme: colorScheme)
        }
        .disabled(isRequesting)
    }

    private var continueButton: some View {
        Button(action: {
            HapticService.shared.success()
            onboardingManager.nextStep()
        }) {
            HStack(spacing: 8) {
                Text("继续")
                    .font(.headline)
                    .fontWeight(.semibold)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(LinearGradient.success)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .floatingShadow(colorScheme: colorScheme)
        }
    }

    private var goToSettingsButton: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.brandWarning)
                Text("权限被拒绝")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            Button(action: openSettings) {
                HStack(spacing: 8) {
                    Text("去设置开启")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Image(systemName: "gear")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.brandPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.brandPrimary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.brandPrimary.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            Button(action: {
                onboardingManager.nextStep()
            }) {
                Text("暂时跳过")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Methods

    private func checkCurrentStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private func requestPermission() {
        isRequesting = true
        HapticService.shared.medium()

        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.authorizationStatus = status
                self.isRequesting = false

                if status == .authorized || status == .limited {
                    HapticService.shared.success()
                    // 自动进入下一步
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onboardingManager.nextStep()
                    }
                } else {
                    HapticService.shared.error()
                }
            }
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

/// 脉冲动画
struct PulseAnimation: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(Color.brandPrimary.opacity(0.2), lineWidth: 1.5)
            .frame(width: 180, height: 180)
            .scaleEffect(isAnimating ? 1.3 : 1.0)
            .opacity(isAnimating ? 0 : 0.4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    OnboardingPermissionRequestView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    OnboardingPermissionRequestView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
