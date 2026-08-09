//
//  WelcomeView.swift
//  PhotoSwipeCleaner
//
//  欢迎页面 - 玻璃拟态设计
//

import SwiftUI

/// 欢迎页面
struct WelcomeView: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.14))
                        .frame(width: 92, height: 92)

                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(.brandPrimary)
                }

                VStack(spacing: 10) {
                    Text("PhotoSort")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("像刷卡一样快速做决定：左滑加入待删，右滑保留或归档。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    featureRow("候选集从截图、视频或最近照片开始，更容易快速清一轮。", icon: "line.3.horizontal.decrease.circle")
                    featureRow("照片只在本机处理，删除会先进系统“最近删除”。", icon: "lock.shield")
                }
            }
            .padding(24)
            .adaptiveLiquidGlass(cornerRadius: 32, tint: .white.opacity(0.1))

            Spacer(minLength: 0)

            Button(action: {
                HapticService.shared.medium()
                onboardingManager.nextStep()
            }) {
                Text("继续")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassProminentButton(cornerRadius: 20, expands: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(_ text: String, icon: String) -> some View {
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
}

// MARK: - Preview
#Preview("Light Mode") {
    WelcomeView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    WelcomeView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
