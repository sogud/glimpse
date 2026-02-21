//
//  GestureTutorialView.swift
//  PhotoSwipeCleaner
//
//  手势教程页面 - 玻璃拟态设计
//

import SwiftUI

/// 手势教程页面
struct GestureTutorialView: View {
    @EnvironmentObject private var onboardingManager: OnboardingManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentGesture: GestureDirection = .none
    @State private var dragOffset = CGSize.zero
    @State private var showHint = false

    private let cardSize: CGFloat = 280
    private let threshold: CGFloat = 60

    var body: some View {
        VStack(spacing: 24) {
            // 标题区域
            headerView

            // 教学卡片区域
            tutorialCard
                .frame(height: 400)

            // 手势指示器
            gestureIndicators

            Spacer()

            // 底部按钮
            bottomButtons
        }
        .padding()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showHint = true
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 12) {
            Text("学习手势操作")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("请按照指示在卡片上滑动\n练习四种整理操作")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .lineSpacing(4)
        }
        .padding(.top, 20)
    }

    private var tutorialCard: some View {
        ZStack {
            // 背景提示箭头
            gestureHints

            // 可滑动卡片 - 玻璃拟态风格
            draggableCard
        }
    }

    private var draggableCard: some View {
        ZStack {
            // 卡片背景 - 玻璃拟态
            RoundedRectangle(cornerRadius: 24)
                .fill(cardColor.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: cardColor.opacity(0.3), radius: 16, x: 0, y: 8)

            // 卡片内容
            VStack(spacing: 20) {
                Image(systemName: cardIcon)
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(.white)

                Text(cardTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(cardDescription)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)
            }
        }
        .frame(width: cardSize, height: cardSize * 1.2)
        .offset(dragOffset)
        .rotationEffect(.degrees(Double(dragOffset.width / 20)))
        .gesture(dragGesture)
        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.8), value: dragOffset)
    }

    private var gestureHints: some View {
        ZStack {
            // 左箭头
            hintArrow(direction: .left, icon: "arrow.left", color: .swipeDelete, isCompleted: isCompleted(.left))
                .offset(x: -140, y: 0)

            // 右箭头
            hintArrow(direction: .right, icon: "arrow.right", color: .swipeKeep, isCompleted: isCompleted(.right))
                .offset(x: 140, y: 0)
        }
        .opacity(showHint ? 0.6 : 0)
        .animation(.easeInOut(duration: 0.5), value: showHint)
    }

    private func hintArrow(direction: GestureDirection, icon: String, color: Color, isCompleted: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isCompleted ? .swipeKeep : color)

            if !isCompleted {
                Image(systemName: arrowIcon(for: direction))
                    .font(.system(size: 18))
                    .foregroundColor(color)
                    .opacity(0.5)
            }
        }
        .frame(width: 56, height: 56)
        .background(
            Circle()
                .fill(color.opacity(0.1))
                .overlay(
                    Circle()
                        .stroke(color.opacity(isCompleted ? 0 : 0.3), lineWidth: 1.5)
                )
        )
    }

    private var gestureIndicators: some View {
        HStack(spacing: 40) {
            gestureIndicator(direction: .left, label: "左滑删除", color: .swipeDelete)
            gestureIndicator(direction: .right, label: "右滑保留", color: .swipeKeep)
        }
    }

    private func gestureIndicator(direction: GestureDirection, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 48, height: 48)

                Circle()
                    .stroke(color.opacity(isCompleted(direction) ? 0 : 0.3), lineWidth: isCompleted(direction) ? 0 : 1.5)
                    .frame(width: 48, height: 48)

                if isCompleted(direction) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: iconForDirection(direction))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
            }

            Text(label)
                .font(.caption)
                .fontWeight(isCompleted(direction) ? .semibold : .regular)
                .foregroundColor(isCompleted(direction) ? color : .secondary)
        }
        .opacity(isCompleted(direction) ? 1.0 : 0.7)
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // 进度提示
            if onboardingManager.isTutorialCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.swipeKeep)
                    Text("太棒了！你已经掌握了所有手势")
                        .font(.subheadline)
                        .foregroundColor(.swipeKeep)
                }
                .transition(.scale.combined(with: .opacity))
            }

            // 继续按钮
            Button(action: {
                onboardingManager.nextStep()
            }) {
                HStack(spacing: 8) {
                    Text(onboardingManager.isTutorialCompleted ? "继续" : "请完成所有手势")
                        .font(.headline)
                        .fontWeight(.semibold)

                    if onboardingManager.isTutorialCompleted {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    onboardingManager.isTutorialCompleted ? LinearGradient.brand : LinearGradient(colors: [.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .floatingShadow(colorScheme: colorScheme)
            }
            .disabled(!onboardingManager.isTutorialCompleted)
            .opacity(onboardingManager.isTutorialCompleted ? 1.0 : 0.6)

            // 跳过按钮
            Button(action: {
                onboardingManager.nextStep()
            }) {
                Text("跳过教程")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation

                // 计算当前手势方向
                let direction = GestureDirection.from(translation: dragOffset, threshold: threshold)
                if direction != currentGesture {
                    currentGesture = direction
                }
            }
            .onEnded { value in
                let direction = GestureDirection.from(translation: dragOffset, threshold: threshold)

                if direction != .none {
                    // 完成手势
                    onboardingManager.markGestureCompleted(direction)
                    HapticService.shared.stepComplete()

                    // 重置卡片位置
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }

                    // 显示庆祝效果（如果完成所有手势）
                    if onboardingManager.isTutorialCompleted {
                        HapticService.shared.celebration()
                    }
                } else {
                    // 未达到阈值，回弹
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Helpers

    private func isCompleted(_ direction: GestureDirection) -> Bool {
        onboardingManager.completedGestures.contains(direction)
    }

    private var cardColor: Color {
        switch currentGesture {
        case .left:
            return .swipeDelete
        case .right:
            return .swipeKeep
        case .up:
            return .brandPrimary
        case .down:
            return .swipeSkip
        case .none:
            return .brandPrimary
        }
    }

    private var cardIcon: String {
        switch currentGesture {
        case .left:
            return "arrow.left.circle.fill"
        case .right:
            return "arrow.right.circle.fill"
        case .up:
            return "folder.fill"
        case .down:
            return "clock.fill"
        case .none:
            return "hand.draw.fill"
        }
    }

    private var cardTitle: String {
        switch currentGesture {
        case .left:
            return "左滑"
        case .right:
            return "右滑"
        case .up:
            return "上滑"
        case .down:
            return "下滑"
        case .none:
            return "试着滑动我"
        }
    }

    private var cardDescription: String {
        switch currentGesture {
        case .left:
            return "左滑移动到指定相册"
        case .right:
            return "右滑移动到指定相册"
        case .up:
            return "上滑将照片归类到相册"
        case .down:
            return "下滑暂时跳过，稍后再决定"
        case .none:
            return "向任意方向滑动体验四种操作"
        }
    }

    private func arrowIcon(for direction: GestureDirection) -> String {
        switch direction {
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .none:
            return ""
        }
    }

    private func iconForDirection(_ direction: GestureDirection) -> String {
        switch direction {
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        case .up:
            return "folder"
        case .down:
            return "clock"
        case .none:
            return ""
        }
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    GestureTutorialView()
        .environmentObject(OnboardingManager())
}

#Preview("Dark Mode") {
    GestureTutorialView()
        .environmentObject(OnboardingManager())
        .preferredColorScheme(.dark)
}
