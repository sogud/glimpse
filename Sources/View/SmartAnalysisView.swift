import Photos
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 智能分析首页，所有结果都来自本地 PhotoKit 与 Vision。
struct SmartAnalysisView: View {
    let onStartCleanup: (SmartInsightGroup) -> Void

    @StateObject private var viewModel = SmartAnalysisViewModel()
    @Environment(\.scenePhase) private var scenePhase

    init(onStartCleanup: @escaping (SmartInsightGroup) -> Void = { _ in }) {
        self.onStartCleanup = onStartCleanup
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoSortAmbientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        statusCard
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("智能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: SmartInsightGroup.self) { group in
                SmartInsightGroupDetailView(group: group, onStartCleanup: onStartCleanup)
            }
            .onAppear {
                viewModel.refreshAuthorizationStatus()
                viewModel.loadCachedSnapshot()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refreshAuthorizationStatus()
                } else if newPhase == .background {
                    viewModel.cancelScan()
                }
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch viewModel.state {
        case .permissionRequired:
            permissionCard
        case .scanning:
            scanningCard
        case .failed(let message):
            errorCard(message)
        case .idle, .completed:
            readyCard
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmartStatusHeader(
                icon: "lock.shield.fill",
                iconColor: .labelOrange,
                title: "需要相册权限",
                subtitle: "智能分析只扫描当前授权范围内的照片。"
            )

            Button {
                if viewModel.authorizationStatus == .denied {
                    openAppSettings()
                } else {
                    viewModel.requestPermissionAndScan()
                }
            } label: {
                Text(viewModel.authorizationStatus == .denied ? "打开设置" : "授予权限并分析")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassProminentButton(cornerRadius: 16, expands: true)
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SmartStatusHeader(
                icon: "sparkles",
                iconColor: .brandPrimary,
                title: viewModel.groups.isEmpty ? "先扫描一遍" : bestGroupTitle,
                subtitle: readySubtitle
            )

            Button {
                viewModel.startScan()
            } label: {
                Text(viewModel.groups.isEmpty ? "开始本地分析" : "重新扫描")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassProminentButton(cornerRadius: 16, expands: true)
            .disabled(!viewModel.isAuthorized)
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }

    private var readySubtitle: String {
        guard let lastScanDate = viewModel.lastScanDate else {
            return "扫描后会直接给出可清理入口。"
        }

        let dateText = lastScanDate.formatted(date: .abbreviated, time: .shortened)
        return "上次 \(dateText) · \(viewModel.analyzedAssetCount) 项"
    }

    private var bestGroupTitle: String {
        guard let bestGroup = prioritizedGroups.first else {
            return "已生成智能分组"
        }
        return "先清 \(bestGroup.title) · \(bestGroup.estimatedSizeText)"
    }

    private var prioritizedGroups: [SmartInsightGroup] {
        viewModel.groups.sorted { left, right in
            if left.estimatedBytes != right.estimatedBytes {
                return left.estimatedBytes > right.estimatedBytes
            }
            return left.count > right.count
        }
    }

    private var secondaryGroups: [SmartInsightGroup] {
        Array(prioritizedGroups.dropFirst())
    }

    private var scanningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmartStatusHeader(
                icon: "waveform.path.ecg",
                iconColor: .brandPrimary,
                title: viewModel.progress?.message ?? "正在分析",
                subtitle: "元数据会先出现，Vision 结果随后补齐。"
            )

            ProgressView(value: viewModel.progress?.fraction ?? 0)
                .tint(.brandPrimary)

            HStack {
                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("停止") {
                    viewModel.cancelScan()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundColor(.brandPrimary)
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }

    private var progressText: String {
        guard let progress = viewModel.progress else { return "准备中" }
        return "\(progress.processed)/\(progress.total)"
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SmartStatusHeader(
                icon: "exclamationmark.triangle.fill",
                iconColor: .labelOrange,
                title: "分析失败",
                subtitle: message
            )

            Button {
                viewModel.startScan()
            } label: {
                Text("重试")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassProminentButton(cornerRadius: 16, expands: true)
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.groups.isEmpty {
            emptyGroupsView
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let topGroup = prioritizedGroups.first {
                    SmartRecommendedCleanupCard(group: topGroup) {
                        onStartCleanup(cleanupGroup(for: topGroup))
                    }
                    .padding(.bottom, 4)
                }

                if !secondaryGroups.isEmpty {
                    sectionTitle("其他入口")

                    ForEach(secondaryGroups) { group in
                        SmartInsightGroupCard(
                            group: group,
                            onStartCleanup: {
                                onStartCleanup(cleanupGroup(for: group))
                            }
                        ) {
                            NavigationLink(value: group) {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var emptyGroupsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmartStatusHeader(
                icon: "tray",
                iconColor: .labelGray,
                title: "暂无可操作分组",
                subtitle: viewModel.isAuthorized ? "没有照片时也可以测试入口；扫描后空分组会自动隐藏。" : "授权后才能扫描。"
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.top, 2)
    }

    private func cleanupGroup(for group: SmartInsightGroup) -> SmartInsightGroup {
        guard group.kind == .similarPhotos else { return group }
        let reviewIdentifiers = group.similarityClusters.flatMap(\.reviewIdentifiers)
        return SmartInsightGroup(
            id: group.id,
            kind: group.kind,
            title: "相似照片建议复核",
            subtitle: "已排除每组推荐保留项",
            localIdentifiers: reviewIdentifiers,
            estimatedBytes: group.similarityClusters.reduce(0) { $0 + $1.recoverableBytes },
            createdAt: group.createdAt,
            suggestedAlbumName: nil,
            similarityClusters: group.similarityClusters
        )
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

private struct SmartStatusHeader: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(iconColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SmartRecommendedCleanupCard: View {
    let group: SmartInsightGroup
    let onStartCleanup: () -> Void

    var body: some View {
        Button(action: onStartCleanup) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: group.kind.iconName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(group.kind.accentColor)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("建议先清理")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(group.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 8)
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(group.estimatedSizeText)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("可复核")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("\(group.count) 项")
                        .font(.subheadline.weight(.semibold))

                    Text("左滑标记删除，最后统一确认")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.primary)
            }
            .padding(18)
            .adaptiveLiquidGlass(cornerRadius: 28, tint: group.kind.accentColor.opacity(0.12), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

private struct SmartInsightGroupCard: View {
    let group: SmartInsightGroup
    let onStartCleanup: () -> Void
    let detailAction: AnyView

    init<DetailAction: View>(
        group: SmartInsightGroup,
        onStartCleanup: @escaping () -> Void,
        @ViewBuilder detailAction: () -> DetailAction
    ) {
        self.group = group
        self.onStartCleanup = onStartCleanup
        self.detailAction = AnyView(detailAction())
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStartCleanup) {
                HStack(spacing: 14) {
                    Image(systemName: group.kind.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(group.kind.accentColor)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(group.kind.accentColor.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)

                        Text("开始清理")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(group.kind.accentColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(group.count) 项")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(group.estimatedSizeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                }
            }
            .buttonStyle(.plain)

            detailAction
        }
        .padding(16)
        .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.08), interactive: true)
    }
}

private struct SmartInsightGroupDetailView: View {
    let group: SmartInsightGroup

    @State private var assets: [PHAsset] = []
    let onStartCleanup: (SmartInsightGroup) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 10)
    ]

    var body: some View {
        ZStack {
            PhotoSortAmbientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard

                    if assets.isEmpty {
                        unavailableAssetsView
                    } else if group.kind == .similarPhotos {
                        similarityClusterList
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                SmartAssetThumbnailView(asset: asset)
                                    .frame(height: 118)
                            }
                        }
                    }

                    cleanupCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear(perform: reloadAssets)
    }

    private var similarityClusterList: some View {
        VStack(spacing: 14) {
            ForEach(group.similarityClusters) { cluster in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("相似组 · \(cluster.memberIdentifiers.count) 张")
                                .font(.headline)
                            Text(cluster.recommendationReasons.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("留 1 张")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.swipeKeep)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(cluster.memberIdentifiers, id: \.self) { identifier in
                                if let asset = assets.first(where: { $0.localIdentifier == identifier }) {
                                    SmartAssetThumbnailView(asset: asset)
                                        .frame(width: 112, height: 128)
                                        .overlay(alignment: .topLeading) {
                                            if identifier == cluster.recommendedKeeperIdentifier {
                                                Text("推荐保留")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(Color.swipeKeep.opacity(0.9), in: Capsule())
                                                    .padding(7)
                                            }
                                        }
                                }
                            }
                        }
                    }

                    Button("只复核其余 \(cluster.reviewIdentifiers.count) 张") {
                        onStartCleanup(reviewGroup(for: cluster))
                    }
                    .font(.subheadline.weight(.semibold))
                    .adaptiveGlassButton(cornerRadius: 14, tint: .white.opacity(0.08), expands: true)
                }
                .padding(16)
                .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.08))
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SmartStatusHeader(
                icon: group.kind.iconName,
                iconColor: group.kind.accentColor,
                title: "\(group.count) 项 · \(group.estimatedSizeText)",
                subtitle: group.subtitle
            )

            if let suggestedAlbumName = group.suggestedAlbumName {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.swipeArchive)
                    Text("可建议相册：\(suggestedAlbumName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 26, tint: .white.opacity(0.08))
    }

    private var unavailableAssetsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("没有可显示的照片")
                .font(.headline)
            Text("资源可能已被删除，或当前相册权限不再包含这些照片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.08))
    }

    private var cleanupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onStartCleanup(allReviewCandidates)
            } label: {
                HStack {
                    Text(group.kind == .similarPhotos ? "复核全部建议删除项" : "开始滑动复核")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .adaptiveGlassButton(cornerRadius: 16, tint: .white.opacity(0.08), expands: true)

            Text("只处理这个分组。左滑标记删除，最后再统一确认。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.08))
    }

    private var allReviewCandidates: SmartInsightGroup {
        guard group.kind == .similarPhotos else { return group }
        return SmartInsightGroup(
            id: group.id,
            kind: group.kind,
            title: "相似照片建议复核",
            subtitle: "已排除每组推荐保留项",
            localIdentifiers: group.similarityClusters.flatMap(\.reviewIdentifiers),
            estimatedBytes: group.similarityClusters.reduce(0) { $0 + $1.recoverableBytes },
            createdAt: group.createdAt,
            suggestedAlbumName: nil,
            similarityClusters: group.similarityClusters
        )
    }

    private func reviewGroup(for cluster: SmartSimilarityCluster) -> SmartInsightGroup {
        SmartInsightGroup(
            id: cluster.id,
            kind: .similarPhotos,
            title: "相似组复核",
            subtitle: "推荐项已保留",
            localIdentifiers: cluster.reviewIdentifiers,
            estimatedBytes: cluster.recoverableBytes,
            createdAt: group.createdAt,
            suggestedAlbumName: nil,
            similarityClusters: [cluster]
        )
    }

    private func reloadAssets() {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: group.localIdentifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetsByIdentifier[asset.localIdentifier] = asset
        }
        assets = group.localIdentifiers.compactMap { assetsByIdentifier[$0] }
    }
}

private struct SmartAssetThumbnailView: View {
    @StateObject private var photoAsset: PhotoAsset

    init(asset: PHAsset) {
        _photoAsset = StateObject(wrappedValue: PhotoAsset(asset: asset))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = photoAsset.image {
                    platformImage(image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.fillSecondary.opacity(0.4))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.82)
                        }
                }

                if photoAsset.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(7)
                        .background(Color.black.opacity(0.42))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
            )
            .onAppear {
                let scale = UIScreen.main.scale
                photoAsset.loadImage(
                    targetSize: CGSize(
                        width: max(geometry.size.width, 1) * scale,
                        height: max(geometry.size.height, 1) * scale
                    ),
                    contentMode: .aspectFill
                )
            }
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}

#Preview {
    SmartAnalysisView()
}
