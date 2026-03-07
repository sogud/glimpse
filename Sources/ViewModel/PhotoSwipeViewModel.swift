import Photos
import SwiftUI

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

    /// 当前选择的源相册（nil 表示所有照片）
    @Published var selectedSourceAlbum: String? {
        didSet {
            UserDefaults.standard.set(selectedSourceAlbum, forKey: "selected_source_album")
        }
    }

    /// 是否显示源相册选择器
    @Published var showSourceAlbumPicker = false

    /// 是否正在执行照片操作
    @Published private(set) var isPerformingAction = false

    // MARK: - Private Properties

    private let service = PhotoLibraryService()

    /// 是否可撤销
    @Published private(set) var canUndo = false

    /// 撤销动作定义
    private enum UndoAction {
        case keep
        case move(albumName: String)
        case delete
    }

    /// 撤销记录
    private struct UndoEntry {
        let action: UndoAction
        let assetIdentifier: String
        let index: Int
    }

    /// 用于撤销操作的栈
    private var undoStack: [UndoEntry] = []

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
            } else {
                currentIndex = 0
                currentPhoto = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// 根据当前配置执行滑动动作
    func performSwipe(
        _ direction: GestureDirection,
        leftSwipeAlbum: String,
        rightSwipeAlbum: String,
        enableHardDelete: Bool
    ) async {
        guard currentPhoto != nil, !isPerformingAction else { return }

        isPerformingAction = true
        defer { isPerformingAction = false }

        switch direction {
        case .left:
            if enableHardDelete || leftSwipeAlbum.isEmpty {
                await deleteCurrentPhoto()
            } else {
                await moveCurrentPhotoToAlbum(leftSwipeAlbum)
            }
        case .right:
            if rightSwipeAlbum.isEmpty {
                keepCurrentPhoto()
            } else {
                await moveCurrentPhotoToAlbum(rightSwipeAlbum)
            }
        default:
            break
        }
    }

    /// 保留当前照片并从当前队列移除
    func keepCurrentPhoto() {
        guard let currentPhoto else { return }
        pushUndo(
            action: .keep,
            assetIdentifier: currentPhoto.asset.localIdentifier,
            index: currentIndex
        )
        removeCurrentPhoto()
    }

    /// 删除当前照片
    func deleteCurrentPhoto() async {
        guard let currentPhoto else { return }

        do {
            let success = try await service.deletePhoto(currentPhoto.asset)
            if success {
                // 删除操作无法真正恢复，这里只支持回到当时位置
                pushUndo(
                    action: .delete,
                    assetIdentifier: currentPhoto.asset.localIdentifier,
                    index: currentIndex
                )
                removeCurrentPhoto()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 移动当前照片到指定相册
    func moveCurrentPhotoToAlbum(_ albumName: String) async {
        guard let currentPhoto else { return }

        do {
            let success = try await service.movePhotoToAlbum(currentPhoto.asset, albumName: albumName)
            if success {
                pushUndo(
                    action: .move(albumName: albumName),
                    assetIdentifier: currentPhoto.asset.localIdentifier,
                    index: currentIndex
                )
                removeCurrentPhoto()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 撤销上一步操作
    func undoLastAction() {
        guard !isPerformingAction, let lastAction = popUndo() else { return }

        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }

            do {
                switch lastAction.action {
                case .keep:
                    ProcessedPhotoManager.shared.removeFromProcessed(lastAction.assetIdentifier)
                case .move(let albumName):
                    _ = try await service.removePhotoFromAlbum(withLocalIdentifier: lastAction.assetIdentifier, albumName: albumName)
                    ProcessedPhotoManager.shared.removeFromProcessed(lastAction.assetIdentifier)
                case .delete:
                    errorMessage = "删除操作受系统限制，无法自动恢复原照片"
                }

                try await loadPhotos()
                restorePhotoPosition(with: lastAction.assetIdentifier, fallbackIndex: lastAction.index)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 检查当前授权状态
    func checkAuthorizationStatus() {
        authorizationStatus = service.currentAuthorizationStatus()
    }

    // MARK: - Private Methods

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

    /// 入栈撤销记录
    private func pushUndo(action: UndoAction, assetIdentifier: String, index: Int) {
        undoStack.append(UndoEntry(action: action, assetIdentifier: assetIdentifier, index: index))
        canUndo = !undoStack.isEmpty
    }

    /// 出栈撤销记录
    private func popUndo() -> UndoEntry? {
        guard !undoStack.isEmpty else { return nil }
        let entry = undoStack.removeLast()
        canUndo = !undoStack.isEmpty
        return entry
    }

    /// 尝试恢复到指定照片或索引
    private func restorePhotoPosition(with assetIdentifier: String, fallbackIndex: Int) {
        guard !allPhotos.isEmpty else {
            currentIndex = 0
            currentPhoto = nil
            return
        }

        if let matchedIndex = allPhotos.firstIndex(where: { $0.asset.localIdentifier == assetIdentifier }) {
            currentIndex = matchedIndex
        } else {
            currentIndex = min(max(0, fallbackIndex), allPhotos.count - 1)
        }

        currentPhoto = allPhotos[currentIndex]
        currentPhoto?.loadImage()
    }
}
