//
//  SourceAlbumPickerView.swift
//  PhotoSort
//
//  源相册选择器 - 选择要整理的照片来源
//

import SwiftUI
import Photos

/// 源相册选择器视图
struct SourceAlbumPickerView: View {
    @ObservedObject var viewModel: PhotoSwipeViewModel
    let workflow: CleanupWorkflow
    let targetAlbum: String?
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [PHAssetCollection] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                PhotoSortAmbientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        selectedAlbumHeader
                        pickerCardStack
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("选择来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(workflow == .delete ? "删图" : "归档")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                loadAlbums()
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var pickerCardStack: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 22) {
                pickerCardStackContent
            }
        } else {
            pickerCardStackContent
        }
    }

    private var pickerCardStackContent: some View {
        VStack(spacing: 18) {
            allPhotosCard
            userAlbumsCard
        }
    }

    private var selectedAlbumHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: workflow == .delete ? "photo.stack.fill" : "folder.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary.opacity(0.14))
                    )

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.selectedSourceAlbum ?? "所有照片")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(18)
        .adaptiveLiquidGlass(cornerRadius: 28, tint: .white.opacity(0.1))
    }

    private var allPhotosCard: some View {
        AlbumPickerSectionCard(
            title: "全部照片",
            footer: workflow == .delete ? "从整个照片库开始筛删，适合做一轮总清理。" : "从整个照片库开始归档，适合快速把值得保留的内容收进目标相册。"
        ) {
            Button(action: {
                selectAlbum(nil)
            }) {
                AlbumPickerOptionRow(
                    icon: "photo.on.rectangle",
                    iconColor: .brandPrimary,
                    title: "所有照片",
                    subtitle: workflow == .delete ? "从整个照片库开始筛删" : "从整个照片库开始归档",
                    isSelected: viewModel.selectedSourceAlbum == nil
                )
            }
            .buttonStyle(SubtleRowButtonStyle())
        }
    }

    private var userAlbumsCard: some View {
        AlbumPickerSectionCard(
            title: "我的相册",
            footer: "选择特定相册可以更有针对性地开始一轮处理。"
        ) {
            if albums.isEmpty {
                if isLoading {
                    AlbumPickerLoadingState(title: "加载相册中...")
                } else {
                    Text("没有用户创建的相册")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                ForEach(Array(albums.enumerated()), id: \.element.localIdentifier) { index, album in
                    Button(action: {
                        selectAlbum(album.localizedTitle)
                    }) {
                        VStack(spacing: 14) {
                            AlbumPickerOptionRow(
                                icon: "folder",
                                iconColor: .labelBlue,
                                title: album.localizedTitle ?? "未知相册",
                                subtitle: "\(album.estimatedAssetCount) 张照片",
                                isSelected: viewModel.selectedSourceAlbum == album.localizedTitle
                            )

                            if index < albums.count - 1 {
                                AlbumPickerDivider()
                            }
                        }
                    }
                    .buttonStyle(SubtleRowButtonStyle())
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadAlbums() {
        isLoading = true

        // 获取所有用户创建的相册
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        var loadedAlbums: [PHAssetCollection] = []
        userAlbums.enumerateObjects { collection, _, _ in
            if collection.localizedTitle != nil {
                loadedAlbums.append(collection)
            }
        }

        // 按照片数量排序
        albums = loadedAlbums.sorted { $0.estimatedAssetCount > $1.estimatedAssetCount }
        isLoading = false
    }

    private func selectAlbum(_ albumName: String?) {
        HapticService.shared.selection()

        Task {
            await viewModel.startSession(
                workflow: workflow,
                preset: .advancedAlbum,
                sourceAlbum: albumName,
                targetAlbum: targetAlbum
            )
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - PHAssetCollection Extension

extension PHAssetCollection {
    /// 估算相册中的照片数量
    var estimatedAssetCount: Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let assets = PHAsset.fetchAssets(in: self, options: options)
        return assets.count
    }
}

// MARK: - Preview
#Preview("Light Mode") {
    SourceAlbumPickerView(
        viewModel: PhotoSwipeViewModel(),
        workflow: .delete,
        targetAlbum: nil
    )
}

#Preview("Dark Mode") {
    SourceAlbumPickerView(
        viewModel: PhotoSwipeViewModel(),
        workflow: .delete,
        targetAlbum: nil
    )
        .preferredColorScheme(.dark)
}
