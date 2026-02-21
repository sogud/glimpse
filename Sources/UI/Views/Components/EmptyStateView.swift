//
//  EmptyStateView.swift
//  PhotoSwipeCleaner
//
//  空状态视图 - 精致的空状态展示
//

import SwiftUI

/// 空状态类型
enum EmptyStateType {
    case noPhotos
    case allComplete
    case noPermission
    case error(String)
    case loading

    var icon: String {
        switch self {
        case .noPhotos:
            return "photo.on.rectangle.angled"
        case .allComplete:
            return "checkmark.circle.fill"
        case .noPermission:
            return "lock.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .loading:
            return "photo.stack"
        }
    }

    var title: String {
        switch self {
        case .noPhotos:
            return "暂无照片"
        case .allComplete:
            return "全部完成！"
        case .noPermission:
            return "需要权限"
        case .error:
            return "出错了"
        case .loading:
            return "加载中"
        }
    }

    var message: String {
        switch self {
        case .noPhotos:
            return "您的相册中没有照片\n快去拍摄一些美好瞬间吧"
        case .allComplete:
            return "您已整理完所有照片\n真棒！"
        case .noPermission:
            return "需要访问您的相册\n才能帮您整理照片"
        case .error(let msg):
            return msg
        case .loading:
            return "正在加载您的照片..."
        }
    }

    var primaryColor: Color {
        switch self {
        case .noPhotos:
            return .secondary
        case .allComplete:
            return .brandSuccess
        case .noPermission:
            return .brandWarning
        case .error:
            return .brandDanger
        case .loading:
            return .brandPrimary
        }
    }
}

/// 空状态视图
struct EmptyStateView: View {
    let type: EmptyStateType
    var action: (() -> Void)?
    var actionTitle: String?

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // 图标
            iconView

            // 文字内容
            textContent

            // 操作按钮
            if let action = action, let title = actionTitle {
                actionButton(action: action, title: title)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Subviews

    private var iconView: some View {
        ZStack {
            // 背景光晕
            Circle()
                .fill(type.primaryColor.opacity(0.08))
                .frame(width: 160, height: 160)
                .blur(radius: 20)
                .scaleEffect(isAnimating ? 1.1 : 1.0)

            // 中圈
            Circle()
                .fill(type.primaryColor.opacity(0.12))
                .frame(width: 120, height: 120)

            // 图标
            Image(systemName: type.icon)
                .font(.system(size: 50, weight: .light))
                .foregroundColor(type.primaryColor)
                .symbolEffect(.bounce, options: .repeating, value: isAnimating)
        }
    }

    private var textContent: some View {
        VStack(spacing: 12) {
            Text(type.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text(type.message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
        }
        .padding(.horizontal, 32)
    }

    private func actionButton(action: @escaping () -> Void, title: String) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: 280)
            .padding(.vertical, 16)
            .background(
                LinearGradient.brand
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 8)
    }
}

// MARK: - 骨架屏加载视图

/// 骨架屏加载视图
struct SkeletonLoadingView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            // 卡片骨架
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 520)
                .overlay(
                    // 闪光效果
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.2),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.5)
                        .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
                        .animation(
                            .linear(duration: 1.5)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))

            // 底部按钮骨架
            HStack(spacing: 32) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 56, height: 56)
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - 权限请求视图

/// 精致的权限请求视图
struct PermissionRequestView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onRequestPermission: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // 图标动画
            ZStack {
                // 外圈光晕
                Circle()
                    .fill(Color.brandPrimary.opacity(0.06))
                    .frame(width: 200, height: 200)
                    .blur(radius: 30)

                // 中圈
                Circle()
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 160, height: 160)

                // 内圈
                Circle()
                    .fill(Color.brandPrimary.opacity(0.15))
                    .frame(width: 120, height: 120)

                // 图标
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.brandPrimary)
            }

            VStack(spacing: 12) {
                Text("需要相册权限")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("为了帮您快速整理照片，\n我们需要访问您的相册。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
            }

            // 权限说明卡片
            VStack(alignment: .leading, spacing: 16) {
                permissionItem(icon: "eye.fill", text: "查看您的照片")
                permissionItem(icon: "trash.fill", text: "删除不需要的照片")
                permissionItem(icon: "folder.fill", text: "移动到相册")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)

            Spacer()

            // 授予权限按钮
            Button(action: onRequestPermission) {
                HStack(spacing: 8) {
                    Text("授予权限")
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
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func permissionItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.1))
                )

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

// MARK: - Preview
#Preview("Empty State - No Photos") {
    EmptyStateView(
        type: .noPhotos,
        action: {},
        actionTitle: "去拍照"
    )
}

#Preview("Empty State - All Complete") {
    EmptyStateView(type: .allComplete)
}

#Preview("Empty State - Loading") {
    EmptyStateView(type: .loading)
}

#Preview("Skeleton Loading") {
    SkeletonLoadingView()
}

#Preview("Permission Request") {
    PermissionRequestView(onRequestPermission: {})
}
