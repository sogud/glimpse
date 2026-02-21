//
//  PhotoCardView.swift
//  PhotoSwipeCleaner
//
//  单个照片卡片视图 - 玻璃拟态设计
//

import SwiftUI
import Photos

/// 单个照片卡片视图
struct PhotoCardView: View {
    @ObservedObject var photoAsset: PhotoAsset
    let offset: CGSize
    let gestureDirection: GestureDirection
    let scale: CGFloat
    let isTopCard: Bool

    @Environment(\.colorScheme) private var colorScheme

    // 视频播放状态
    @State private var isPlayingVideo = false

    // 根据偏移量计算覆盖层透明度
    private var overlayOpacity: Double {
        let maxOffset: CGFloat = 100
        let totalOffset = abs(offset.width) + abs(offset.height)
        return min(Double(totalOffset) / Double(maxOffset), 0.7)
    }

    // 计算旋转角度 - 增强拖拽时的旋转效果
    private var rotationAngle: Double {
        // 限制最大旋转角度为 ±15 度
        let maxRotation: Double = 15
        let rawRotation = Double(offset.width / 20)
        return max(-maxRotation, min(maxRotation, rawRotation))
    }

    // 根据拖拽状态计算缩放
    private var dragScale: CGFloat {
        guard isTopCard else { return scale }
        let dragDistance = abs(offset.width)
        // 拖拽时略微缩小，产生"被提起"的感觉
        let scaleReduction = min(dragDistance / 1000, 0.05)
        return scale * (1 - scaleReduction)
    }

    // 根据拖拽状态计算阴影
    private var shadowRadius: CGFloat {
        guard isTopCard else { return 10 }
        let dragDistance = abs(offset.width)
        // 拖拽时阴影变大，增强悬浮感
        let shadowIncrease = min(dragDistance / 50, 10)
        return 20 + shadowIncrease
    }

    init(
        photoAsset: PhotoAsset,
        offset: CGSize = .zero,
        gestureDirection: GestureDirection = .none,
        scale: CGFloat = 1.0,
        isTopCard: Bool = true
    ) {
        self.photoAsset = photoAsset
        self.offset = offset
        self.gestureDirection = gestureDirection
        self.scale = scale
        self.isTopCard = isTopCard
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 拍立得边框背景
                polaroidBackground

                // 照片内容区域
                photoContentArea(in: geometry)

                // 玻璃拟态遮罩层
                glassOverlay

                // 根据滑动方向显示不同的覆盖层
                swipeOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(dragScale)
        .opacity(isTopCard ? 1.0 : 0.9)
        .offset(offset)
        .rotationEffect(.degrees(rotationAngle))
        .shadow(
            color: Color.black.opacity(0.3),
            radius: shadowRadius,
            x: 0,
            y: 10
        )
        .padding(.horizontal, 20)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.9, blendDuration: 0), value: offset)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: dragScale)
        // 当视图出现时加载图片
        .onAppear {
            photoAsset.loadImage()
        }
        // 当照片资源改变时（切换卡片），重置视频播放状态并加载图片
        .onChange(of: photoAsset.id) {
            isPlayingVideo = false
            photoAsset.loadImage()
        }
        // 当开始滑动时，停止视频播放
        .onChange(of: offset) {
            if abs(offset.width) > 5 && isPlayingVideo {
                isPlayingVideo = false
            }
        }
    }

    // 拍立得风格背景
    private var polaroidBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
            )
    }

    // MARK: - Subviews

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.backgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4), lineWidth: 0.5)
            )
    }

    // 照片内容区域 - 拍立得风格
    private func photoContentArea(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // 照片主体
            photoImage(in: geometry)
                .padding(12)
                .padding(.top, 12)

            // 底部日期标签 - 拍立得风格
            dateLabel
                .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func photoImage(in geometry: GeometryProxy) -> some View {
        ZStack {
            if isPlayingVideo {
                // 内嵌视频播放器 - 使用 UIViewRepresentable 实现真正的手势穿透
                InlineVideoPlayer(asset: photoAsset.asset, isPlaying: $isPlayingVideo)
                    .frame(maxWidth: geometry.size.width - 48, maxHeight: geometry.size.height - 100)
            } else if let image = photoAsset.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width - 48, maxHeight: geometry.size.height - 100)

                // 视频播放图标
                if photoAsset.isVideo {
                    videoOverlay
                }
            } else if photoAsset.isLoading {
                loadingView
                    .frame(height: geometry.size.height - 100)
            } else {
                placeholderView
                    .frame(height: geometry.size.height - 100)
            }
        }
    }

    // 视频覆盖层 - 播放图标和时长
    private var videoOverlay: some View {
        VStack {
            Spacer()

            // 可点击的播放按钮
            Button {
                isPlayingVideo = true
            } label: {
                ZStack {
                    // 播放按钮背景
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 60, height: 60)

                    // 播放图标
                    Image(systemName: "play.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .offset(x: 2)
                }
            }

            Spacer()

            // 视频时长
            if let duration = photoAsset.videoDuration {
                HStack {
                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.caption)
                        Text(duration)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(12)
                }
            }
        }
    }

    // 日期标签 - 复古胶片风格
    private var dateLabel: some View {
        HStack {
            Spacer()

            VStack(spacing: 2) {
                if let date = photoAsset.creationDate {
                    // 日期 - 大号
                    Text(formatDate(date))
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundColor(.black.opacity(0.8))

                    // 时间 - 小号
                    Text(formatTime(date))
                        .font(.system(size: 11, weight: .regular, design: .serif))
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 计算照片在容器中的显示尺寸
    private func calculateSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        // 限制最大宽度为容器宽度的 90%
        let maxWidth = containerSize.width * 0.9
        // 限制最大高度为容器高度的 85%
        let maxHeight = containerSize.height * 0.85

        let imageAspect = imageSize.width / imageSize.height
        let maxAspect = maxWidth / maxHeight

        if imageAspect > maxAspect {
            // 宽图：以宽度为基准
            let width = min(imageSize.width, maxWidth)
            return CGSize(width: width, height: width / imageAspect)
        } else {
            // 高图或方图：以高度为基准
            let height = min(imageSize.height, maxHeight)
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.brandPrimary)

            Text("加载中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))

            Text("无法加载照片")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Glass Overlay

    private var glassOverlay: some View {
        Color.clear // 拍立得风格不需要玻璃遮罩，日期直接显示在白底上
    }

    // MARK: - Swipe Overlay

    @ViewBuilder
    private var swipeOverlay: some View {
        switch gestureDirection {
        case .left:
            overlayContent(
                icon: "trash.fill",
                text: "删除",
                color: .swipeDelete,
                alignment: .leading
            )
        case .right:
            overlayContent(
                icon: "checkmark.circle.fill",
                text: "保留",
                color: .swipeKeep,
                alignment: .trailing
            )
        case .up:
            overlayContent(
                icon: "folder.fill",
                text: "归档",
                color: .swipeArchive,
                alignment: .top
            )
        case .down:
            overlayContent(
                icon: "clock.fill",
                text: "跳过",
                color: .swipeSkip,
                alignment: .bottom
            )
        case .none:
            Color.clear
        }
    }

    private func overlayContent(
        icon: String,
        text: String,
        color: Color,
        alignment: Alignment
    ) -> some View {
        ZStack {
            // 渐变遮罩
            LinearGradient(
                colors: [
                    color.opacity(overlayOpacity * 0.8),
                    color.opacity(overlayOpacity * 0.3)
                ],
                startPoint: alignment == .leading ? .leading : alignment == .trailing ? .trailing : alignment == .top ? .top : .bottom,
                endPoint: .center
            )

            // 图标和文字
            VStack {
                if alignment == .top {
                    overlayLabel(icon: icon, text: text, color: color)
                        .padding(.top, 50)
                    Spacer()
                } else if alignment == .bottom {
                    Spacer()
                    overlayLabel(icon: icon, text: text, color: color)
                        .padding(.bottom, 50)
                } else if alignment == .leading {
                    HStack {
                        overlayLabel(icon: icon, text: text, color: color)
                            .padding(.leading, 40)
                        Spacer()
                    }
                } else {
                    HStack {
                        Spacer()
                        overlayLabel(icon: icon, text: text, color: color)
                            .padding(.trailing, 40)
                    }
                }
            }
        }
    }

    private func overlayLabel(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .semibold))

            Text(text)
                .font(.headline)
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(color.opacity(0.95))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 4)
    }

}

// MARK: - Preview
#Preview("Light Mode") {
    PhotoCardView(
        photoAsset: PhotoAsset(asset: PHAsset()),
        offset: .zero,
        gestureDirection: .none
    )
    .padding()
}

#Preview("Dark Mode") {
    PhotoCardView(
        photoAsset: PhotoAsset(asset: PHAsset()),
        offset: .zero,
        gestureDirection: .left
    )
    .preferredColorScheme(.dark)
    .padding()
}
