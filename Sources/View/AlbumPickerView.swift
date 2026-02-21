import SwiftUI
import Photos

/// 相册选择器视图
struct AlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PhotoSwipeViewModel

    @State private var newAlbumName = ""
    @State private var showingNewAlbumAlert = false
    @State private var albums: [PHAssetCollection] = []
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("加载相册中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // 创建新相册选项
                        Button(action: {
                            showingNewAlbumAlert = true
                        }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("创建新相册")
                            }
                        }

                        // 现有相册列表
                        ForEach(albums, id: \.localIdentifier) { album in
                            Button(action: {
                                selectAlbum(album)
                            }) {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(album.localizedTitle ?? "未知相册")
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("选择相册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAlbums()
            }
            .alert("创建新相册", isPresented: $showingNewAlbumAlert) {
                TextField("相册名称", text: $newAlbumName)
                Button("创建") {
                    createNewAlbum()
                }
                Button("取消", role: .cancel) {
                    newAlbumName = ""
                }
            } message: {
                Text("请输入新相册的名称")
            }
        }
    }

    /// 加载用户相册
    private func loadAlbums() {
        isLoading = true

        // 只获取用户创建的相册，不包括系统相册
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )

        var loadedAlbums: [PHAssetCollection] = []
        userAlbums.enumerateObjects { collection, _, _ in
            // 过滤掉空相册（可选）
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            if assets.count > 0 || collection.localizedTitle != nil {
                loadedAlbums.append(collection)
            }
        }

        albums = loadedAlbums
        isLoading = false
    }

    /// 选择相册
    private func selectAlbum(_ album: PHAssetCollection) {
        guard let currentPhoto = viewModel.currentPhoto else {
            dismiss()
            return
        }

        if let albumName = album.localizedTitle {
            viewModel.movePhotoToAlbum(currentPhoto.asset, albumName: albumName)
        }

        dismiss()
    }

    /// 创建新相册
    private func createNewAlbum() {
        guard !newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        guard let currentPhoto = viewModel.currentPhoto else {
            dismiss()
            return
        }

        viewModel.movePhotoToAlbum(currentPhoto.asset, albumName: newAlbumName)
        newAlbumName = ""
        dismiss()
    }
}

