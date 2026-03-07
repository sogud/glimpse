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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // 背景
            backgroundView

            // 根据当前步骤显示不同内容
            contentView
        }
        .animation(.easeInOut(duration: 0.3), value: onboardingManager.currentStep)
    }

    // MARK: - Subviews

    private var backgroundView: some View {
        ZStack {
            // 渐变背景 - 柔和装饰
            LinearGradient.background
                .ignoresSafeArea()

            // 装饰性背景元素 - 更柔和
            GeometryReader { geometry in
                Circle()
                    .fill(Color.brandPrimary.opacity(0.03))
                    .frame(width: 350, height: 350)
                    .offset(x: -120, y: -100)
                    .blur(radius: 60)

                Circle()
                    .fill(Color.purple.opacity(0.02))
                    .frame(width: 400, height: 400)
                    .offset(x: geometry.size.width - 150, y: geometry.size.height - 200)
                    .blur(radius: 60)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch onboardingManager.currentStep {
        case .welcome:
            WelcomeView()

        case .tutorial:
            GestureTutorialView()

        case .permission:
            OnboardingPermissionRequestView()

        case .albumSetup:
            OnboardingAlbumSetupView()

        case .complete:
            completionView
        }
    }

    private var completionView: some View {
        VStack(spacing: 32) {
            Spacer()

            // 完成动画 - 玻璃拟态风格
            ZStack {
                // 外圈光晕
                Circle()
                    .fill(Color.swipeKeep.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .blur(radius: 20)

                Circle()
                    .fill(Color.swipeKeep.opacity(0.12))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(Color.swipeKeep.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 70, weight: .medium))
                    .foregroundColor(.swipeKeep)
                    .symbolEffect(.bounce)
            }

            VStack(spacing: 16) {
                Text("准备就绪！")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("你已经掌握了所有技巧\n开始整理你的相册吧")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }

            Spacer()

            Button(action: {
                HapticService.shared.celebration()
                onboardingManager.completeOnboarding()
            }) {
                HStack(spacing: 8) {
                    Text("开始整理")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient.success
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .floatingShadow(colorScheme: colorScheme)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .padding()
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
