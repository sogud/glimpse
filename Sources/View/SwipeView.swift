import SwiftUI

/// 滑动交互视图 - 极简卡片设计
struct SwipeView: View {
    @ObservedObject var viewModel: PhotoSwipeViewModel
    @Binding var interactionProgress: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    // 手势状态
    @State private var dragOffset = CGSize.zero
    @State private var isProcessing = false
    @State private var swipeObserver: NSObjectProtocol?

    // 阈值
    private let threshold: CGFloat = 80
    private let maxOffset: CGFloat = 200

    // 用户设置
    @AppStorage("swipeRightAlbum") private var swipeRightAlbum: String = ""

    private var activeWorkflow: CleanupWorkflow {
        viewModel.activeWorkflow ?? .delete
    }

    private var currentArchiveAlbum: String? {
        if let sessionAlbum = viewModel.selectedTargetAlbum?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionAlbum.isEmpty {
            return sessionAlbum
        }
        let trimmed = swipeRightAlbum.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var swipeProgress: CGFloat {
        min(abs(dragOffset.width) / 140, 1)
    }

    private var swipeColor: Color {
        if dragOffset.width < 0 {
            return activeWorkflow == .delete ? .swipeDelete : .swipeSkip
        }
        if dragOffset.width > 0 {
            if activeWorkflow == .organize || currentArchiveAlbum != nil {
                return .swipeArchive
            }
            return .swipeKeep
        }
        return .clear
    }

    var body: some View {
        ZStack {
            if swipeProgress > 0.01 {
                swipeFeedbackGlow
            }

            cardStack

            if viewModel.allPhotos.isEmpty && !viewModel.isLoading {
                emptyStateView
            }
        }
        .onAppear {
            interactionProgress = 0
            preloadUpcomingPhotos()
            if swipeObserver == nil {
                swipeObserver = NotificationCenter.default.addObserver(forName: .triggerSwipe, object: nil, queue: .main) { notification in
                    if let direction = notification.object as? GestureDirection {
                        performSwipe(direction)
                    }
                }
            }
        }
        .onDisappear {
            interactionProgress = 0
            if let swipeObserver {
                NotificationCenter.default.removeObserver(swipeObserver)
                self.swipeObserver = nil
            }
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

    private func preloadUpcomingPhotos() {
        for offset in 0...1 {
            if let photo = photoAt(offset: offset) {
                photo.loadImage()
            }
        }
    }


    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
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
                scale: 1.0,
                isTopCard: true
            )

            // 方向标签（滑动时显示）
            directionLabels
        }
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture)
    }

    // MARK: - Direction Labels

    private var directionLabels: some View {
        ZStack {
            // 左滑 - 移动到左滑相册
            if dragOffset.width < 0 {
                HStack {
                    leftSwipeLabel
                        .opacity(swipeProgress)
                        .scaleEffect(0.94 + (swipeProgress * 0.06))
                        .offset(x: 12 - (swipeProgress * 12))
                    Spacer()
                }
                .padding(.leading, 20)
            }

            // 右滑 - 移动到右滑相册
            if dragOffset.width > 0 {
                HStack {
                    Spacer()
                    rightSwipeLabel
                        .opacity(swipeProgress)
                        .scaleEffect(0.94 + (swipeProgress * 0.06))
                        .offset(x: -12 + (swipeProgress * 12))
                }
                .padding(.trailing, 20)
            }
        }
    }

    private var leftSwipeLabel: some View {
        let isDeleteWorkflow = activeWorkflow == .delete
        let label = isDeleteWorkflow ? "待删除" : "跳过"
        let color = isDeleteWorkflow ? Color.swipeDelete : Color.swipeSkip
        return VStack(spacing: 4) {
            Image(systemName: isDeleteWorkflow ? "trash.fill" : "arrow.left")
                .font(.system(size: 20, weight: .semibold))
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .adaptiveLiquidGlass(cornerRadius: 18, tint: color.opacity(0.28))
        .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private var rightSwipeLabel: some View {
        let isArchiveAction = activeWorkflow == .organize || currentArchiveAlbum != nil
        let label = currentArchiveAlbum ?? "保留"
        let iconName = isArchiveAction ? "folder.badge.plus" : "arrow.right"
        let tint = isArchiveAction ? Color.swipeArchive : Color.swipeKeep
        return VStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .adaptiveLiquidGlass(cornerRadius: 18, tint: tint.opacity(0.28))
        .shadow(color: tint.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    private var swipeFeedbackGlow: some View {
        GeometryReader { geometry in
            Circle()
                .fill(swipeColor.opacity(0.22))
                .frame(width: geometry.size.width * 0.62, height: geometry.size.width * 0.62)
                .blur(radius: 40)
                .offset(
                    x: dragOffset.width < 0
                        ? (-geometry.size.width * 0.32)
                        : (geometry.size.width * 0.32),
                    y: -geometry.size.height * 0.02
                )
                .opacity(swipeProgress)
                .animation(.easeOut(duration: 0.12), value: swipeProgress)
        }
        .allowsHitTesting(false)
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

                Text("本轮处理完成")
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

                interactionProgress = swipeProgress
            }
            .onEnded { value in
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
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        dragOffset = .zero
                        interactionProgress = 0
                    }
                }
            }
    }

    // MARK: - Helpers

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
            if activeWorkflow == .delete {
                HapticService.shared.swipeDelete()
            } else {
                HapticService.shared.swipeSkip()
            }
        case .right:
            if activeWorkflow == .organize || currentArchiveAlbum != nil {
                HapticService.shared.swipeArchive()
            } else {
                HapticService.shared.swipeKeep()
            }
        }

        Task { @MainActor in
            let exitX = action == .left ? -maxOffset * 2.0 : maxOffset * 2.0
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                dragOffset = CGSize(width: exitX, height: -16)
                interactionProgress = 1
            }

            try? await Task.sleep(nanoseconds: 120_000_000)

            let direction: GestureDirection = action == .left ? .left : .right
            await viewModel.performSwipe(direction, archiveAlbum: currentArchiveAlbum)

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                dragOffset = .zero
                interactionProgress = 0
            }

            isProcessing = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                preloadUpcomingPhotos()
            }
        }
    }

    private enum SwipeAction {
        case left
        case right
    }
}
