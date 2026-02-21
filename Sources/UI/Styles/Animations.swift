//
//  Animations.swift
//  PhotoSwipeCleaner
//
//  动画系统 - 定义标准动画曲线和参数
//

import SwiftUI

// MARK: - 动画曲线

extension Animation {
    /// 默认过渡动画
    static let standard = Animation.easeInOut(duration: 0.3)

    /// 快速过渡动画
    static let quick = Animation.easeOut(duration: 0.2)

    /// 慢速过渡动画
    static let slow = Animation.easeInOut(duration: 0.5)

    /// 弹簧动画 - 卡片返回
    static let cardReturn = Animation.spring(response: 0.5, dampingFraction: 0.7)

    /// 弹簧动画 - 卡片滑出
    static let cardSwipe = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// 弹簧动画 - 按钮按压
    static let buttonPress = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// 弹簧动画 - 弹窗出现
    static let modalAppear = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// 交互式弹簧动画
    static let interactive = Animation.interactiveSpring(
        response: 0.4,
        dampingFraction: 0.8,
        blendDuration: 0
    )
}

// MARK: - 弹簧参数

struct SpringParameters {
    /// 响应时间
    let response: Double

    /// 阻尼系数
    let dampingFraction: Double

    /// 混合持续时间
    let blendDuration: Double

    /// 创建弹簧动画
    var animation: Animation {
        Animation.spring(
            response: response,
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }

    /// 创建交互式弹簧动画
    var interactiveAnimation: Animation {
        Animation.interactiveSpring(
            response: response,
            dampingFraction: dampingFraction,
            blendDuration: blendDuration
        )
    }
}

extension SpringParameters {
    /// 默认弹簧
    static let `default` = SpringParameters(
        response: 0.4,
        dampingFraction: 0.8,
        blendDuration: 0
    )

    /// 弹性弹簧 - 用于卡片返回
    static let bouncy = SpringParameters(
        response: 0.5,
        dampingFraction: 0.6,
        blendDuration: 0
    )

    /// 柔和弹簧 - 用于页面过渡
    static let gentle = SpringParameters(
        response: 0.6,
        dampingFraction: 0.9,
        blendDuration: 0
    )

    /// 快速弹簧 - 用于按钮反馈
    static let snappy = SpringParameters(
        response: 0.3,
        dampingFraction: 0.7,
        blendDuration: 0
    )
}

// MARK: - 过渡动画

extension AnyTransition {
    /// 卡片滑出过渡
    static var cardSwipe: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9)),
            removal: .opacity.combined(with: .offset(x: 500))
        )
    }

    /// 卡片滑入过渡
    static var cardEnter: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        )
    }

    /// 从底部滑入
    static var slideFromBottom: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// 淡入淡出
    static var fade: AnyTransition {
        .opacity
    }

    /// 缩放淡入淡出
    static var scaleFade: AnyTransition {
        .scale.combined(with: .opacity)
    }
}

// MARK: - 视图修饰符

struct AnimatedScaleModifier: ViewModifier {
    let isActive: Bool
    let scale: CGFloat
    let animation: Animation

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? scale : 1.0)
            .animation(animation, value: isActive)
    }
}

struct AnimatedOffsetModifier: ViewModifier {
    let offset: CGSize
    let animation: Animation

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .animation(animation, value: offset)
    }
}

struct AnimatedOpacityModifier: ViewModifier {
    let opacity: Double
    let animation: Animation

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .animation(animation, value: opacity)
    }
}

extension View {
    /// 应用缩放动画
    func animatedScale(
        _ isActive: Bool,
        scale: CGFloat = 0.95,
        animation: Animation = .buttonPress
    ) -> some View {
        modifier(AnimatedScaleModifier(isActive: isActive, scale: scale, animation: animation))
    }

    /// 应用位移动画
    func animatedOffset(
        _ offset: CGSize,
        animation: Animation = .standard
    ) -> some View {
        modifier(AnimatedOffsetModifier(offset: offset, animation: animation))
    }

    /// 应用透明度动画
    func animatedOpacity(
        _ opacity: Double,
        animation: Animation = .standard
    ) -> some View {
        modifier(AnimatedOpacityModifier(opacity: opacity, animation: animation))
    }

    /// 按压效果
    func pressable(scale: CGFloat = 0.95) -> some View {
        self.modifier(PressableModifier(scale: scale))
    }
}

// MARK: - 按压效果修饰符

struct PressableModifier: ViewModifier {
    let scale: CGFloat
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(.buttonPress, value: isPressed)
            .onLongPressGesture(
                minimumDuration: .infinity,
                maximumDistance: .infinity,
                pressing: { pressing in
                    isPressed = pressing
                },
                perform: {}
            )
    }
}

// MARK: - 动画状态管理

/// 管理视图动画状态的类
class AnimationState: ObservableObject {
    @Published var isAnimating = false
    @Published var progress: Double = 0

    private var timer: Timer?

    /// 开始动画
    func start(duration: TimeInterval = 1.0) {
        isAnimating = true
        progress = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.progress += 0.016 / duration

            if self.progress >= 1.0 {
                self.progress = 1.0
                self.isAnimating = false
                self.timer?.invalidate()
            }
        }
    }

    /// 停止动画
    func stop() {
        isAnimating = false
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
