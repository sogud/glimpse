//
//  Colors.swift
//  PhotoSwipeCleaner
//
//  颜色系统 - 支持深色模式与玻璃拟态设计
//

import SwiftUI

// MARK: - 品牌色 (柔和饱和度)

extension Color {
    /// 品牌主色 - 柔和蓝
    static let brandPrimary = Color(red: 0.357, green: 0.557, blue: 0.937)

    /// 成功色 - 柔和绿
    static let brandSuccess = Color(red: 0.298, green: 0.851, blue: 0.392)

    /// 警告色 - 保持
    static let brandWarning = Color(red: 1, green: 0.584, blue: 0)

    /// 危险色 - 柔和红
    static let brandDanger = Color(red: 1, green: 0.42, blue: 0.42)
}

// MARK: - 滑动操作色 (柔和版)

extension Color {
    /// 保留 - 柔和绿
    static let swipeKeep = Color(red: 0.298, green: 0.851, blue: 0.392)

    /// 删除 - 柔和红
    static let swipeDelete = Color(red: 1, green: 0.42, blue: 0.42)

    /// 归档 - 柔和蓝
    static let swipeArchive = Color(red: 0.357, green: 0.557, blue: 0.937)

    /// 跳过 - 柔和灰
    static let swipeSkip = Color(red: 0.6, green: 0.6, blue: 0.65)
}

// MARK: - 背景色

extension Color {
    /// 主背景
    static let backgroundPrimary: Color = .init(.systemBackground)

    /// 次级背景
    static let backgroundSecondary: Color = .init(.secondarySystemBackground)

    /// 三级背景
    static let backgroundTertiary: Color = .init(.tertiarySystemBackground)

    /// 分组背景
    static let backgroundGrouped: Color = .init(.systemGroupedBackground)

    /// 次级分组背景
    static let backgroundGroupedSecondary: Color = .init(.secondarySystemGroupedBackground)
}

// MARK: - 玻璃拟态背景色

extension Color {
    /// 玻璃背景 - 浅色模式
    static let glassLight = Color.white.opacity(0.75)

    /// 玻璃背景 - 深色模式
    static let glassDark = Color.black.opacity(0.6)

    /// 玻璃背景 - 自动适应
    static var glassBackground: Color {
        Color(.systemBackground).opacity(0.8)
    }

    /// 玻璃边框
    static let glassBorder = Color.white.opacity(0.2)
}

// MARK: - 填充色

extension Color {
    /// 一级填充
    static let fillPrimary: Color = .init(.systemFill)

    /// 二级填充
    static let fillSecondary: Color = .init(.secondarySystemFill)

    /// 三级填充
    static let fillTertiary: Color = .init(.tertiarySystemFill)
}

// MARK: - 标签色

extension Color {
    /// 蓝色标签
    static let labelBlue: Color = .init(.systemBlue)

    /// 绿色标签
    static let labelGreen: Color = .init(.systemGreen)

    /// 靛蓝标签
    static let labelIndigo: Color = .init(.systemIndigo)

    /// 橙色标签
    static let labelOrange: Color = .init(.systemOrange)

    /// 粉色标签
    static let labelPink: Color = .init(.systemPink)

    /// 紫色标签
    static let labelPurple: Color = .init(.systemPurple)

    /// 红色标签
    static let labelRed: Color = .init(.systemRed)

    /// 青色标签
    static let labelTeal: Color = .init(.systemTeal)

    /// 黄色标签
    static let labelYellow: Color = .init(.systemYellow)

    /// 灰色标签
    static let labelGray: Color = .init(.systemGray)

    /// 二级灰色
    static let labelGray2: Color = .init(.systemGray2)

    /// 三级灰色
    static let labelGray3: Color = .init(.systemGray3)
}

// MARK: - 渐变

extension LinearGradient {
    /// 品牌渐变 - 柔和
    static let brand = LinearGradient(
        colors: [
            Color(red: 0.357, green: 0.557, blue: 0.937),
            Color(red: 0.6, green: 0.4, blue: 0.9)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 成功渐变
    static let success = LinearGradient(
        colors: [Color.swipeKeep, Color.mint],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 背景渐变 - 柔和装饰
    static let background = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.99, blue: 1.0),
            Color(red: 0.86, green: 0.94, blue: 1.0).opacity(0.5),
            Color(red: 0.86, green: 0.98, blue: 0.96).opacity(0.42),
            Color(red: 0.99, green: 1.0, blue: 1.0)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 玻璃渐变
    static let glass = LinearGradient(
        colors: [
            Color.white.opacity(0.4),
            Color.white.opacity(0.1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 深色玻璃渐变
    static let glassDark = LinearGradient(
        colors: [
            Color.white.opacity(0.15),
            Color.white.opacity(0.05)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - 阴影参数

extension View {
    /// 卡片阴影 - 多层柔和
    func cardShadow(colorScheme: ColorScheme) -> some View {
        self
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                radius: 20,
                x: 0,
                y: 8
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.04),
                radius: 40,
                x: 0,
                y: 20
            )
    }

    /// 玻璃拟态阴影
    func glassShadow(colorScheme: ColorScheme) -> some View {
        self
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                radius: 16,
                x: 0,
                y: 4
            )
    }

    /// 悬浮按钮阴影
    func floatingShadow(colorScheme: ColorScheme) -> some View {
        self
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

// MARK: - 玻璃拟态修饰符

struct GlassmorphismModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    var cornerRadius: CGFloat = 24
    var blurRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(colorScheme == .dark ? Color.glassDark : Color.glassLight)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// 应用玻璃拟态效果
    func glassmorphism(cornerRadius: CGFloat = 24, blurRadius: CGFloat = 20) -> some View {
        modifier(GlassmorphismModifier(cornerRadius: cornerRadius, blurRadius: blurRadius))
    }

    /// 液态玻璃风格面板（mac/iOS 通用回退实现）
    func liquidGlassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    /// 原生液态玻璃外观，低系统版本回退到 material。
    func adaptiveLiquidGlass(
        cornerRadius: CGFloat = 20,
        tint: Color = .white.opacity(0.08),
        interactive: Bool = false
    ) -> some View {
        modifier(
            AdaptiveLiquidGlassModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive
            )
        )
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.14), Color.white.opacity(0.04)]
                                        : [Color.white.opacity(0.45), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.3), lineWidth: 1)
                    )
            )
    }
}

private struct AdaptiveLiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let tint: Color
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        .regular
                            .tint(tint)
                            .interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                content
                    .glassEffect(
                        .regular.tint(tint),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color.white.opacity(0.12), Color.white.opacity(0.03)]
                                            : [Color.white.opacity(0.42), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.3), lineWidth: 1)
                        )
                )
        }
    }
}
