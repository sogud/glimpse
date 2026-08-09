//
//  OnboardingView.swift
//  PhotoSwipeCleaner
//
//  新手引导主容器 - 玻璃拟态设计
//

import SwiftUI

/// 新手引导主视图
struct OnboardingView: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager

    var body: some View {
        ZStack {
            PhotoSortAmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 20) {
                progressChrome
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                contentView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: onboardingManager.currentStep)
    }

    @ViewBuilder
    private var contentView: some View {
        switch onboardingManager.currentStep {
        case .welcome:
            WelcomeView()

        case .permission:
            OnboardingPermissionRequestView()

        case .complete:
            completionView
        }
    }

    private var progressChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(currentStepTitle)
                    .font(.headline)

                Spacer()

                Text(currentStepCounter)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: onboardingManager.progress)
                .tint(.brandPrimary)
        }
        .padding(.horizontal, 4)
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.swipeKeep.opacity(0.14))
                        .frame(width: 88, height: 88)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundColor(.swipeKeep)
                }

                VStack(spacing: 12) {
                    Text("准备就绪！")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("左滑标记待删除，最后统一确认删除。\n可选右滑归档到相册。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                }

                VStack(alignment: .leading, spacing: 10) {
                    completionRow("快速决策：左右滑处理候选照片", icon: "arrow.left.arrow.right")
                    completionRow("删除安全：整轮确认一次", icon: "tray.full.fill")
                }
            }
            .padding(24)
            .adaptiveLiquidGlass(cornerRadius: 32, tint: .white.opacity(0.1))

            Spacer(minLength: 0)

            Button(action: {
                HapticService.shared.celebration()
                onboardingManager.completeOnboarding()
            }) {
                HStack(spacing: 8) {
                    Text("开始删图")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .adaptiveGlassProminentButton(cornerRadius: 20, expands: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentStepTitle: String {
        switch onboardingManager.currentStep {
        case .welcome:
            return "欢迎使用"
        case .permission:
            return "权限设置"
        case .complete:
            return "开始前确认"
        }
    }

    private var currentStepCounter: String {
        switch onboardingManager.currentStep {
        case .welcome:
            return "1 / 3"
        case .permission:
            return "2 / 3"
        case .complete:
            return "3 / 3"
        }
    }

    private func completionRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.swipeKeep)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.swipeKeep.opacity(0.12))
                )

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    OnboardingView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    OnboardingView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
