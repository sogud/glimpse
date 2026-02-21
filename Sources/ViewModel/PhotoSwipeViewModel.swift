import Photos
import SwiftUI
import Combine

/// 主要的视图模型，协调Service和View之间的交互
@MainActor
class PhotoSwipeViewModel: ObservableObject {
    // MARK: - Published Properties

    /// 当前照片索引
    @Published var currentIndex = 0

    /// 当前照片资产
    @Published var currentPhoto: PhotoAsset?

    /// 所有照片资产
    @Published var allPhotos: [PhotoAsset] = []

    /// 加载状态
    @Published var isLoading = false

    /// 错误信息
    @Published var errorMessage: String?

    /// 权限状态
    @Published var authorizationStatus: PhotoLibraryService.AuthorizationStatus = .notDetermined

    /// 触发相册选择器的标志
    @Published var showAlbumPicker = false

    /// 当前选择的源相册（nil 表示所有照片）
    @Published var selectedSourceAlbum: String? {
        didSet {
            UserDefaults.standard.set(selectedSourceAlbum, forKey: "selected_source_album")
        }
    }

    /// 是否显示源相册选择器
    @Published var showSourceAlbumPicker = false

    // MARK: - Private Properties

    let service = PhotoLibraryService()
    private var cancellables = Set<AnyCancellable>()

    // 用于撤销操作的栈
    private var undoStack: [(action: String, asset: PHAsset, index: Int)] = []

    /// 撤销栈是否为空
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    // MARK: - Initialization

    init() {
        // 加载保存的源相册设置
        let savedAlbum = UserDefaults.standard.string(forKey: "selected_source_album")
        self.selectedSourceAlbum = savedAlbum
        checkAuthorizationStatus()
    }

    // MARK: - Public Methods

    /// 请求相册权限
    func requestPermission() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let status = await service.requestAuthorization()
            authorizationStatus = status

            if status == .authorized || status == .limited {
                try await loadPhotos()
            }
        } catch {
            errorMessage = "权限请求失败: \(error.localizedDescription)"
        }
    }

    /// 加载照片
    func loadPhotos() async throws {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryService.PhotoLibraryError.insufficientPermission
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // 获取用户设置中的目标相册名称
            let leftSwipeAlbum = UserDefaults.standard.string(forKey: "leftSwipeAlbum") ?? ""
            let rightSwipeAlbum = UserDefaults.standard.string(forKey: "rightSwipeAlbum") ?? ""
            var excludeAlbums: [String] = []
            if !leftSwipeAlbum.isEmpty {
                excludeAlbums.append(leftSwipeAlbum)
            }
            if !rightSwipeAlbum.isEmpty && !excludeAlbums.contains(rightSwipeAlbum) {
                excludeAlbums.append(rightSwipeAlbum)
            }

            // 从指定相册或所有照片获取
            let assets = try service.fetchPhotos(fromAlbum: selectedSourceAlbum, excludeAlbums: excludeAlbums)

            // 过滤掉已处理的照片
            let processedManager = ProcessedPhotoManager.shared
            let filteredAssets = assets.filter { !processedManager.isProcessed($0.localIdentifier) }

            allPhotos = filteredAssets.map { PhotoAsset(asset: $0) }

            if !allPhotos.isEmpty {
                currentIndex = 0
                currentPhoto = allPhotos[0]
                // 预加载第一张图片，使用较大的目标尺寸
                currentPhoto?.loadImage()
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 处理滑动手势
    /// - Parameter direction: 滑动方向
    func handleSwipe(_ direction: GestureDirection) {
        guard let currentPhoto = currentPhoto else { return }

        switch direction {
        case .right:
            // 保留照片，移动到下一张
            keepPhoto()
        case .left:
            // 删除照片
            deletePhoto(currentPhoto.asset)
        case .up:
            // 移动到相册（需要用户选择相册）
            showAlbumPicker = true
        case .down:
            // 跳过/稍后处理
            skipPhoto()
        case .none:
            break
        }
    }

    /// 保留当前照片并移动到下一张
    func keepPhoto() {
        // 记录为已处理
        if let currentPhoto = currentPhoto {
            ProcessedPhotoManager.shared.markAsProcessed(currentPhoto.asset.localIdentifier)
        }
        moveToNextPhoto()
    }

    /// 删除当前照片
    func deletePhoto(_ asset: PHAsset) {
        Task {
            do {
                // 保存撤销信息
                undoStack.append(("delete", asset, currentIndex))

                let success = try await service.deletePhoto(asset)
                if success {
                    removeCurrentPhoto()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// 移动照片到指定相册
    func movePhotoToAlbum(_ asset: PHAsset, albumName: String) {
        Task {
            do {
                // 保存撤销信息
                undoStack.append(("move", asset, currentIndex))

                let success = try await service.movePhotoToAlbum(asset, albumName: albumName)
                if success {
                    removeCurrentPhoto()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// 移动当前照片到指定相册（用于设置中配置的相册）
    func moveToAlbum(_ albumName: String) {
        guard let currentPhoto = currentPhoto else { return }
        movePhotoToAlbum(currentPhoto.asset, albumName: albumName)
    }

    /// 跳过当前照片（移动到下一张）
    func skipPhoto() {
        // 记录为已处理
        if let currentPhoto = currentPhoto {
            ProcessedPhotoManager.shared.markAsProcessed(currentPhoto.asset.localIdentifier)
        }
        moveToNextPhoto()
    }

    /// 撤销上一步操作
    func undoLastAction() {
        guard !undoStack.isEmpty else { return }

        let lastAction = undoStack.removeLast()

        // 对于删除和移动操作，我们只需要重新加载照片列表
        // 因为实际的照片数据可能已经改变，最安全的方式是重新获取
        Task {
            do {
                try await loadPhotos()
                // 尝试恢复到之前的位置
                if lastAction.index < allPhotos.count {
                    currentIndex = lastAction.index
                    currentPhoto = allPhotos[currentIndex]
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// 检查当前授权状态
    func checkAuthorizationStatus() {
        authorizationStatus = service.currentAuthorizationStatus()
    }

    // MARK: - Private Methods

    /// 移动到下一张照片
    private func moveToNextPhoto() {
        guard currentIndex < allPhotos.count - 1 else {
            // 如果是最后一张，可以考虑循环到第一张或者停止
            // 这里选择停止在最后一张
            return
        }

        currentIndex += 1
        currentPhoto = allPhotos[currentIndex]
        currentPhoto?.loadImage()
    }

    /// 移除当前照片（从本地列表中）
    private func removeCurrentPhoto() {
        guard !allPhotos.isEmpty else { return }
        
        // 记录为已处理
        let removedPhoto = allPhotos[currentIndex]
        ProcessedPhotoManager.shared.markAsProcessed(removedPhoto.asset.localIdentifier)

        allPhotos.remove(at: currentIndex)

        if allPhotos.isEmpty {
            currentPhoto = nil
            currentIndex = 0
        } else if currentIndex >= allPhotos.count {
            // 如果删除的是最后一张，移动到新的最后一张
            currentIndex = allPhotos.count - 1
            currentPhoto = allPhotos[currentIndex]
        } else {
            // 保持在同一索引位置（下一张照片会自动填充）
            currentPhoto = allPhotos[currentIndex]
        }

        // 预加载当前照片
        currentPhoto?.loadImage()
    }
}