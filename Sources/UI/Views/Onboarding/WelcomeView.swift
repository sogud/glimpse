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
    @Environment(\.colorScheme) private var colorScheme

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 品牌动画区域
            brandAnimation

            Spacer()

            // 标题和描述
            textContent

            Spacer()

            // 底部按钮
            bottomButtons
        }
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Subviews

    private var brandAnimation: some View {
        ZStack {
            // 背景圆环 - 柔和版
            ForEach(0..<3) { index in
                Circle()
                    .stroke(Color.brandPrimary.opacity(0.08), lineWidth: 1.5)
                    .frame(width: 200 + CGFloat(index * 40), height: 200 + CGFloat(index * 40))
                    .scaleEffect(isAnimating ? 1 : 0.8)
                    .opacity(isAnimating ? 1 : 0)
                    .animation(
                        .easeInOut(duration: 1).delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }

            // 主图标容器 - 玻璃拟态
            ZStack {
                // 渐变背景 - 柔和
                RoundedRectangle(cornerRadius: 36)
                    .fill(
                        LinearGradient.brand
                    )
                    .frame(width: 140, height: 140)
                    .floatingShadow(colorScheme: colorScheme)

                // 图标
                Image(systemName: "photo.stack")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(.white)
                    .symbolEffect(.bounce, options: .repeating, value: isAnimating)
            }
            .scaleEffect(isAnimating ? 1 : 0.5)
            .opacity(isAnimating ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: isAnimating)

            // 漂浮的照片图标 - 柔和色彩
            floatingIcons
        }
        .frame(height: 300)
    }

    private var floatingIcons: some View {
        Group {
            // 截图图标
            floatingIcon(
                name: "crop",
                color: .swipeSkip,
                position: CGPoint(x: -100, y: -80),
                delay: 0.3
            )

            // 相册图标
            floatingIcon(
                name: "folder.fill",
                color: .brandPrimary,
                position: CGPoint(x: 100, y: -60),
                delay: 0.4
            )

            // 删除图标
            floatingIcon(
                name: "trash.fill",
                color: .swipeDelete,
                position: CGPoint(x: -80, y: 80),
                delay: 0.5
            )

            // 对勾图标
            floatingIcon(
                name: "checkmark.circle.fill",
                color: .swipeKeep,
                position: CGPoint(x: 90, y: 90),
                delay: 0.6
            )
        }
    }

    private func floatingIcon(name: String, color: Color, position: CGPoint, delay: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(color)
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(Color(.systemBackground))
                    .shadow(color: color.opacity(0.15), radius: 8, x: 0, y: 4)
            )
            .overlay(
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
            .offset(x: position.x, y: position.y)
            .scaleEffect(isAnimating ? 1 : 0)
            .opacity(isAnimating ? 1 : 0)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7).delay(delay),
                value: isAnimating
            )
    }

    private var textContent: some View {
        VStack(spacing: 16) {
            Text("PhotoSwipe")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            + Text("Cleaner")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.brandPrimary)

            Text("像刷短视频一样\n快速整理你的相册")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)

            // 特性标签
            HStack(spacing: 16) {
                featureTag(icon: "bolt.fill", text: "高效")
                featureTag(icon: "hand.tap.fill", text: "简单")
                featureTag(icon: "lock.shield.fill", text: "安全")
            }
            .padding(.top, 8)
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: isAnimating)
    }

    private func featureTag(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.brandPrimary)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.brandPrimary.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var bottomButtons: some View {
        VStack(spacing: 16) {
            Button(action: {
                HapticService.shared.medium()
                onboardingManager.nextStep()
            }) {
                HStack(spacing: 8) {
                    Text("开始体验")
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
                .floatingShadow(colorScheme: colorScheme)
            }

            // 页码指示器
            PageIndicator(currentPage: 0, totalPages: OnboardingStep.allCases.count)
        }
        .padding(.bottom, 20)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.6), value: isAnimating)
    }
}

/// 页码指示器
struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.brandPrimary : Color.secondary.opacity(0.2))
                    .frame(width: index == currentPage ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
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
