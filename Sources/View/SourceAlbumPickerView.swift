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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var albums: [PHAssetCollection] = []
    @State private var isLoading = true
    @State private var photoCount: Int = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Group {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        GlassEffectContainer(spacing: 16) {
                            selectedAlbumHeader
                        }
                    } else {
                        selectedAlbumHeader
                    }
                }
                .padding()
                .background(colorScheme == .dark ? Color.black : Color.clear)

                Divider()

                // 相册列表
                if isLoading {
                    Spacer()
                    ProgressView("加载相册中...")
                    Spacer()
                } else {
                    List {
                        // 所有照片选项
                        allPhotosSection

                        // 用户相册列表
                        userAlbumsSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("选择相册")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
                updatePhotoCount()
            }
        }
    }

    // MARK: - Subviews

    private var selectedAlbumHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.brandPrimary)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("当前选择")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(viewModel.selectedSourceAlbum ?? "所有照片")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }

            HStack {
                Text("共 \(photoCount) 张照片待整理")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding()
        .adaptiveLiquidGlass(cornerRadius: 24, tint: .white.opacity(0.1))
    }

    private var allPhotosSection: some View {
        Section {
            Button(action: {
                selectAlbum(nil)
            }) {
                HStack(spacing: 16) {
                    // 图标
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.brandPrimary.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                            .foregroundColor(.brandPrimary)
                    }

                    // 文字
                    VStack(alignment: .leading, spacing: 2) {
                        Text("所有照片")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text("从整个照片库开始整理")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 选中标记
                    if viewModel.selectedSourceAlbum == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.brandPrimary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        } header: {
            Text("全部照片")
        }
    }

    private var userAlbumsSection: some View {
        Section {
            if albums.isEmpty {
                Text("没有用户创建的相册")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(albums, id: \.localIdentifier) { album in
                    Button(action: {
                        selectAlbum(album.localizedTitle)
                    }) {
                        HStack(spacing: 16) {
                            // 图标
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.labelBlue.opacity(0.15))
                                    .frame(width: 44, height: 44)

                                Image(systemName: "folder")
                                    .font(.system(size: 20))
                                    .foregroundColor(.labelBlue)
                            }

                            // 文字
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.localizedTitle ?? "未知相册")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text("\(album.estimatedAssetCount) 张照片")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 选中标记
                            if viewModel.selectedSourceAlbum == album.localizedTitle {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.brandPrimary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        } header: {
            Text("我的相册")
        } footer: {
            Text("选择特定相册可以更有针对性地整理照片")
                .font(.caption)
                .foregroundColor(.secondary)
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

    private func updatePhotoCount() {
        photoCount = viewModel.allPhotos.count
    }

    private func selectAlbum(_ albumName: String?) {
        viewModel.selectedSourceAlbum = albumName
        HapticService.shared.selection()

        // 重新加载照片
        Task {
            do {
                // 先清空当前照片列表，强制刷新
                await MainActor.run {
                    viewModel.allPhotos = []
                    viewModel.currentPhoto = nil
                }
                
                try await viewModel.loadPhotos()
                
                await MainActor.run {
                    updatePhotoCount()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    dismiss()
                }
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
    SourceAlbumPickerView(viewModel: PhotoSwipeViewModel())
}

#Preview("Dark Mode") {
    SourceAlbumPickerView(viewModel: PhotoSwipeViewModel())
        .preferredColorScheme(.dark)
}
