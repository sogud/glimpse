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

    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.14))
                        .frame(width: 92, height: 92)

                    Image(systemName: "lock.shield")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(.brandPrimary)
                }

                VStack(spacing: 10) {
                    Text("需要相册权限")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("只用于展示候选照片，并在你确认后把删除操作交给系统相册。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    permissionRow("读取照片与视频，仅在本机显示。", icon: "photo")
                    permissionRow("先加入待删清单，最后统一确认。", icon: "trash")
                }
            }
            .padding(24)
            .adaptiveLiquidGlass(cornerRadius: 32, tint: .white.opacity(0.1))

            Spacer(minLength: 0)

            bottomSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkCurrentStatus()
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 12) {
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
                Text("照片只在本机处理，不上传")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .adaptiveLiquidGlass(cornerRadius: 16, tint: .white.opacity(0.05))
        }
    }

    private var requestButton: some View {
        Button(action: requestPermission) {
            HStack(spacing: 10) {
                if isRequesting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text("授予权限")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassProminentButton(cornerRadius: 20, expands: true)
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
            }
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassProminentButton(cornerRadius: 20, expands: true)
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
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.primary)
            .adaptiveGlassButton(cornerRadius: 20, tint: .brandPrimary.opacity(0.12), expands: true)

            Button(action: {
                onboardingManager.completeOnboarding()
            }) {
                Text("稍后再说")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(cornerRadius: 20, tint: .white.opacity(0.08), expands: true)
        }
    }

    private func permissionRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.12))
                )

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
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
