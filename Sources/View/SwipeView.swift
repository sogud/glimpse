import SwiftUI
import UIKit

/// 滑动交互视图 - 极简卡片设计
struct SwipeView: View {
    @ObservedObject var viewModel: PhotoSwipeViewModel

    @Environment(\.colorScheme) private var colorScheme

    // 手势状态
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var isProcessing = false

    // 阈值
    private let threshold: CGFloat = 80
    private let maxOffset: CGFloat = 200

    // 用户设置
    @AppStorage("swipeLeftAlbum") private var swipeLeftAlbum: String = ""
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""
    @AppStorage("enableHardDelete") private var enableHardDelete = false

    // 卡片堆叠 - 拍立得风格
    private let cardOffsetY: CGFloat = 6
    private let cardScaleStep: CGFloat = 0.02

    var body: some View {
        ZStack {
            // 卡片堆叠
            cardStack

            // 空状态
            if viewModel.allPhotos.isEmpty && !viewModel.isLoading {
                emptyStateView
            }
        }
        .onAppear {
            // 加载所有可见卡片的图片
            for offset in 0...2 {
                if let photo = photoAt(offset: offset) {
                    photo.loadImage()
                }
            }
            // 监听按钮触发的滑动
            NotificationCenter.default.addObserver(forName: .triggerSwipe, object: nil, queue: .main) { notification in
                if let direction = notification.object as? GestureDirection {
                    performSwipe(direction)
                }
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: .triggerSwipe, object: nil)
        }
    }

    private func performSwipe(_ direction: GestureDirection) {
        switch direction {
        case .left:
            performSwipeAction(.left)
        case .right:
            performSwipeAction(.right)
        default:
            break
        }
    }


    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
            // 第三张卡片（最底层）
            if let thirdPhoto = photoAt(offset: 2) {
                PhotoCardView(
                    photoAsset: thirdPhoto,
                    offset: .zero,
                    gestureDirection: .none,
                    scale: 1.0 - (cardScaleStep * 2),
                    isTopCard: false
                )
                .offset(y: cardOffsetY * 2)
                .opacity(0.4)
            }

            // 第二张卡片
            if let secondPhoto = photoAt(offset: 1) {
                PhotoCardView(
                    photoAsset: secondPhoto,
                    offset: .zero,
                    gestureDirection: .none,
                    scale: 1.0 - cardScaleStep,
                    isTopCard: false
                )
                .offset(y: cardOffsetY)
                .opacity(0.7)
            }

            // 第一张卡片（当前卡片）
            if let currentPhoto = viewModel.currentPhoto {
                topCard(photo: currentPhoto)
            } else if viewModel.isLoading {
                loadingCard
            }
        }
    }

    // MARK: - Top Card

    private func topCard(photo: PhotoAsset) -> some View {
        ZStack {
            // 卡片主体
            PhotoCardView(
                photoAsset: photo,
                offset: dragOffset,
                gestureDirection: currentDirection,
                scale: 1.0,
                isTopCard: true
            )

            // 方向标签（滑动时显示）
            directionLabels

            // 计数器（左上角）
            photoCounter
        }
        .gesture(dragGesture)
    }

    // MARK: - Direction Labels

    private var directionLabels: some View {
        ZStack {
            // 左滑 - 移动到左滑相册
            if dragOffset.width < 0 {
                HStack {
                    leftSwipeLabel
                        .opacity(min(abs(dragOffset.width) / threshold, 1.0))
                    Spacer()
                }
                .padding(.leading, 32)
            }

            // 右滑 - 移动到右滑相册
            if dragOffset.width > 0 {
                HStack {
                    Spacer()
                    rightSwipeLabel
                        .opacity(min(abs(dragOffset.width) / threshold, 1.0))
                }
                .padding(.trailing, 32)
            }
        }
    }

    private var leftSwipeLabel: some View {
        let label = enableHardDelete ? "删除" : (swipeLeftAlbum.isEmpty ? "左滑" : swipeLeftAlbum)
        let color = enableHardDelete ? Color.swipeDelete : Color.swipeArchive
        return VStack(spacing: 4) {
            Image(systemName: enableHardDelete ? "trash.fill" : "arrow.left")
                .font(.system(size: 20, weight: .semibold))
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(color.opacity(0.95))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
        .rotationEffect(.degrees(-8))
    }

    private var rightSwipeLabel: some View {
        let label = swipeRightAlbum.isEmpty ? "保留" : swipeRightAlbum
        return VStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .semibold))
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.swipeKeep.opacity(0.95))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.swipeKeep.opacity(0.4), radius: 8, x: 0, y: 4)
        .rotationEffect(.degrees(8))
    }

    // MARK: - Photo Counter

    private var photoCounter: some View {
        VStack {
            HStack {
                Text("\(viewModel.currentIndex + 1)/\(viewModel.allPhotos.count)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.4))
                    )

                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.brandPrimary)

            Text("加载照片中...")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.backgroundSecondary)
        )
        .cardShadow(colorScheme: colorScheme)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            // 勾选图标
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.brandSuccess)

            VStack(spacing: 8) {
                Text("全部完成！")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("本次整理完成")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isProcessing else { return }
                isDragging = true

                // 添加阻力效果
                let resistance: CGFloat = 0.9
                dragOffset = CGSize(
                    width: value.translation.width * resistance,
                    height: value.translation.height * resistance * 0.3 // 减少垂直移动
                )

                // 限制最大偏移
                if abs(dragOffset.width) > maxOffset {
                    dragOffset.width = maxOffset * (dragOffset.width > 0 ? 1 : -1)
                }
            }
            .onEnded { value in
                isDragging = false

                let horizontal = value.translation.width
                let velocity = value.predictedEndLocation.x - value.location.x

                // 判断是否达到阈值或有足够速度
                if abs(horizontal) > threshold || abs(velocity) > 100 {
                    if horizontal < 0 || velocity < -100 {
                        // 左滑
                        performSwipeAction(.left)
                    } else {
                        // 右滑
                        performSwipeAction(.right)
                    }
                } else {
                    // 回弹 - 无动画直接复位
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Helpers

    /// 当前滑动方向
    private var currentDirection: GestureDirection {
        if dragOffset.width < -threshold / 2 {
            return .left
        } else if dragOffset.width > threshold / 2 {
            return .right
        }
        return .none
    }

    /// 获取指定偏移位置的图片
    private func photoAt(offset: Int) -> PhotoAsset? {
        let targetIndex = viewModel.currentIndex + offset
        guard targetIndex >= 0 && targetIndex < viewModel.allPhotos.count else {
            return nil
        }
        return viewModel.allPhotos[targetIndex]
    }

    /// 执行滑动操作 - 直接切换，无动画
    private func performSwipeAction(_ action: SwipeAction) {
        guard !isProcessing else { return }
        isProcessing = true

        // 触觉反馈
        switch action {
        case .left:
            if enableHardDelete {
                HapticService.shared.swipeDelete()
            } else if !swipeLeftAlbum.isEmpty {
                HapticService.shared.swipeArchive()
            } else {
                HapticService.shared.swipeDelete()
            }
        case .right:
            HapticService.shared.swipeKeep()
        }

        // 直接执行业务逻辑，无动画
        switch action {
        case .left:
            if enableHardDelete {
                viewModel.handleSwipe(.left)
            } else if !swipeLeftAlbum.isEmpty {
                viewModel.moveToAlbum(swipeLeftAlbum)
            } else {
                viewModel.handleSwipe(.left)
            }
        case .right:
            if !swipeRightAlbum.isEmpty {
                viewModel.moveToAlbum(swipeRightAlbum)
            } else {
                viewModel.handleSwipe(.right)
            }
        }
        
        // 重置状态
        dragOffset = .zero
        isProcessing = false

        // 预加载新可见卡片的图片
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for offset in 0...2 {
                if let photo = photoAt(offset: offset) {
                    photo.loadImage()
                }
            }
        }
    }

    private enum SwipeAction {
        case left
        case right
    }
}
