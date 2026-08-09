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
    let scale: CGFloat
    let isTopCard: Bool

    @Environment(\.colorScheme) private var colorScheme

    // 视频播放状态
    @State private var isPlayingVideo = false
    @State private var isVideoLoading = false

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
        guard isTopCard else { return 8 }
        let dragDistance = abs(offset.width)
        let shadowIncrease = min(dragDistance / 60, 8)
        return 16 + shadowIncrease
    }

    init(
        photoAsset: PhotoAsset,
        offset: CGSize = .zero,
        scale: CGFloat = 1.0,
        isTopCard: Bool = true
    ) {
        self.photoAsset = photoAsset
        self.offset = offset
        self.scale = scale
        self.isTopCard = isTopCard
    }

    var body: some View {
        GeometryReader { geometry in
            let requestSize = imageRequestSize(for: geometry.size)

            ZStack {
                photoContentArea(in: geometry)
            }
            .onAppear {
                photoAsset.loadImage(targetSize: requestSize)
                photoAsset.loadOriginalFileSize()
            }
            .onChange(of: photoAsset.id) {
                isPlayingVideo = false
                isVideoLoading = false
                photoAsset.loadImage(targetSize: requestSize)
                photoAsset.loadOriginalFileSize()
            }
            .onChange(of: requestSize) { _, newSize in
                photoAsset.loadImage(targetSize: newSize)
            }
            .onDisappear {
                photoAsset.cancelOriginalFileSizeLoad(resetState: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(dragScale)
        .opacity(isTopCard ? 1.0 : 0.9)
        .offset(offset)
        .rotationEffect(.degrees(rotationAngle))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.14),
            radius: shadowRadius,
            x: 0,
            y: 8
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        // 当开始滑动时，停止视频播放
        .onChange(of: offset) {
            if abs(offset.width) > 5 && isPlayingVideo {
                isPlayingVideo = false
                isVideoLoading = false
            }
        }
    }

    // MARK: - Subviews

    // 照片内容区域 - 保持内容优先，只保留必要视频控制
    private func photoContentArea(in geometry: GeometryProxy) -> some View {
        photoImage(in: geometry)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .bottom) {
                bottomMetadataOverlay
            }
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28), lineWidth: 0.8)
            )
            .compositingGroup()
    }

    @ViewBuilder
    private func photoImage(in geometry: GeometryProxy) -> some View {
        ZStack {
            if isPlayingVideo {
                ZStack {
                    InlineVideoPlayer(
                        asset: photoAsset.asset,
                        isPlaying: $isPlayingVideo,
                        isLoading: $isVideoLoading
                    )
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)

                    if isVideoLoading {
                        videoLoadingOverlay
                    }
                }
            } else if let image = photoAsset.image {
                platformImageView(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)

                // 视频播放图标
                if photoAsset.isVideo {
                    videoPlayOverlay
                }
            } else if photoAsset.isLoading {
                loadingView
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            } else {
                placeholderView
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            }
        }
    }

    private func platformImageView(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }

    private func imageRequestSize(for containerSize: CGSize) -> CGSize {
        #if canImport(UIKit)
        let scale = UIScreen.main.scale
        #else
        let scale: CGFloat = 2
        #endif

        return CGSize(
            width: max(containerSize.width, 1) * scale,
            height: max(containerSize.height, 1) * scale
        )
    }

    private var bottomMetadataOverlay: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if shouldShowFileSizeChip {
                fileSizeChip
            }

            Spacer(minLength: 0)

            if let duration = photoAsset.videoDuration {
                durationChip(duration)
            }
        }
        .padding(10)
    }

    private var shouldShowFileSizeChip: Bool {
        switch photoAsset.originalFileSizeState {
        case .idle:
            return false
        case .loadingRemote, .ready, .failed:
            return true
        }
    }

    @ViewBuilder
    private var fileSizeChip: some View {
        switch photoAsset.originalFileSizeState {
        case .idle:
            EmptyView()
        case .loadingRemote:
            metadataChip(icon: "icloud.and.arrow.down", text: "获取大小...")
        case .ready(let bytes):
            metadataChip(
                icon: photoAsset.isVideo ? "film.fill" : "photo.fill",
                text: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            )
        case .failed:
            metadataChip(icon: "exclamationmark.triangle.fill", text: "大小不可用")
        }
    }

    // 视频覆盖层 - 播放图标
    private var videoPlayOverlay: some View {
        VStack {
            Spacer()

            // 可点击的播放按钮
            Button {
                isVideoLoading = true
                isPlayingVideo = true
            } label: {
                ZStack {
                    Circle()
                        .frame(width: 56, height: 56)
                        .adaptiveLiquidGlass(cornerRadius: 28, tint: .white.opacity(0.12), interactive: true)

                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(x: 2)
                }
            }

            Spacer()
        }
    }

    private func durationChip(_ duration: String) -> some View {
        metadataChip(icon: "video.fill", text: duration)
    }

    private func metadataChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .adaptiveLiquidGlass(cornerRadius: 14, tint: .black.opacity(0.08))
    }

    private var videoLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)

            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.1)

                Text("载入视频中...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .adaptiveLiquidGlass(cornerRadius: 18, tint: .white.opacity(0.08))
        }
        .allowsHitTesting(false)
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
}

// MARK: - Preview
#Preview("Light Mode") {
    PhotoCardView(
        photoAsset: PhotoAsset(asset: PHAsset()),
        offset: .zero
    )
    .padding()
}

#Preview("Dark Mode") {
    PhotoCardView(
        photoAsset: PhotoAsset(asset: PHAsset()),
        offset: .zero
    )
    .preferredColorScheme(.dark)
    .padding()
}
