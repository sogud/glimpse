import Photos
import Foundation

/// 封装所有与系统相册交互的逻辑，供ViewModel调用
/// 不包含任何UI，不依赖第三方库
class PhotoLibraryService {

    // MARK: - 权限管理

    /// 相册权限状态
    enum AuthorizationStatus {
        case authorized
        case limited
        case denied
        case notDetermined
    }

    /// 获取当前相册权限状态
    func currentAuthorizationStatus() -> AuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// 请求相册读写权限
    /// - Returns: 授权状态结果
    func requestAuthorization() async -> AuthorizationStatus {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                switch status {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .limited:
                    continuation.resume(returning: .limited)
                case .denied, .restricted:
                    continuation.resume(returning: .denied)
                case .notDetermined:
                    continuation.resume(returning: .notDetermined)
                @unknown default:
                    continuation.resume(returning: .denied)
                }
            }
        }
    }

    // MARK: - 获取照片资源

    /// 获取照片PHAsset数组
    /// - Parameters:
    ///   - limit: 最大数量限制，默认为1000
    ///   - excludeAlbums: 要排除的相册名称列表（已分类到这些相册的照片将被过滤掉）
    /// - Returns: PHAsset数组
    /// - Throws: PhotoLibraryError
    func fetchPhotos(limit: Int = 1000, excludeAlbums: [String] = []) throws -> [PHAsset] {
        // 检查权限
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        // 获取需要排除的asset localIdentifiers集合
        var excludedIdentifiers = Set<String>()
        if !excludeAlbums.isEmpty {
            let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            collections.enumerateObjects { collection, _, _ in
                if let title = collection.localizedTitle, excludeAlbums.contains(title) {
                    let assets = PHAsset.fetchAssets(in: collection, options: nil)
                    assets.enumerateObjects { asset, _, _ in
                        excludedIdentifiers.insert(asset.localIdentifier)
                    }
                }
            }
        }

        // 创建获取选项
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 同时获取图片和视频
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.fetchLimit = limit

        // 获取资产
        let assets = PHAsset.fetchAssets(with: options)
        var result: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            // 排除已在目标相册中的照片
            if !excludedIdentifiers.contains(asset.localIdentifier) {
                result.append(asset)
            }
        }

        return result
    }

    /// 从指定相册获取照片
    /// - Parameters:
    ///   - albumName: 相册名称，如果为nil则获取所有照片
    ///   - limit: 最大数量限制，默认为1000
    ///   - excludeAlbums: 要排除的相册名称列表
    /// - Returns: PHAsset数组
    /// - Throws: PhotoLibraryError
    func fetchPhotos(fromAlbum albumName: String?, limit: Int = 1000, excludeAlbums: [String] = []) throws -> [PHAsset] {
        // 如果没有指定相册，返回所有照片
        guard let albumName = albumName, !albumName.isEmpty else {
            return try fetchPhotos(limit: limit, excludeAlbums: excludeAlbums)
        }

        // 检查权限
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        // 查找指定相册
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var targetCollection: PHAssetCollection?
        collections.enumerateObjects { collection, _, _ in
            if collection.localizedTitle == albumName {
                targetCollection = collection
                return
            }
        }

        // 如果找不到相册，返回空数组
        guard let collection = targetCollection else {
            return []
        }

        // 获取需要排除的asset localIdentifiers集合
        var excludedIdentifiers = Set<String>()
        if !excludeAlbums.isEmpty {
            collections.enumerateObjects { collection, _, _ in
                if let title = collection.localizedTitle, excludeAlbums.contains(title) {
                    let assets = PHAsset.fetchAssets(in: collection, options: nil)
                    assets.enumerateObjects { asset, _, _ in
                        excludedIdentifiers.insert(asset.localIdentifier)
                    }
                }
            }
        }

        // 创建获取选项
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 同时获取图片和视频
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.fetchLimit = limit

        // 从指定相册获取资产
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        var result: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            // 排除已在目标相册中的照片
            if !excludedIdentifiers.contains(asset.localIdentifier) {
                result.append(asset)
            }
        }

        return result
    }

    // MARK: - 删除照片

    /// 删除单个照片
    /// - Parameter asset: 要删除的PHAsset
    /// - Returns: 操作是否成功
    /// - Throws: PhotoLibraryError
    func deletePhoto(_ asset: PHAsset) async throws -> Bool {
        // 检查权限
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    if let error = error {
                        // 检查是否是资产已不存在的错误
                        if (error as NSError).code == -1 {
                            // 资产可能已被删除，视为成功
                            continuation.resume(returning: true)
                        } else {
                            continuation.resume(throwing: PhotoLibraryError.deletionFailed(error.localizedDescription))
                        }
                    } else {
                        continuation.resume(throwing: PhotoLibraryError.deletionFailed("Unknown error"))
                    }
                }
            }
        }
    }

    // MARK: - 移动照片到相册

    /// 移动照片到指定相册
    /// - Parameters:
    ///   - asset: 要移动的PHAsset
    ///   - albumName: 目标相册名称
    /// - Returns: 操作是否成功
    /// - Throws: PhotoLibraryError
    func movePhotoToAlbum(_ asset: PHAsset, albumName: String) async throws -> Bool {
        // 检查权限
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        // 确保相册名称有效
        guard !albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PhotoLibraryError.albumCreationFailed("Album name is empty")
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                // 在 performChanges 块中查找现有相册
                let userCollections = PHAssetCollection.fetchAssetCollections(
                    with: .album,
                    subtype: .any,
                    options: nil
                )

                var targetCollection: PHAssetCollection?
                userCollections.enumerateObjects { collection, _, _ in
                    if collection.localizedTitle == albumName {
                        targetCollection = collection
                        return
                    }
                }

                if let targetCollection = targetCollection {
                    // 相册已存在，直接添加资产
                    let addRequest = PHAssetCollectionChangeRequest(for: targetCollection)
                    addRequest?.addAssets([asset] as NSArray)
                } else {
                    // 创建新相册并添加资产
                    let creationRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    creationRequest.addAssets([asset] as NSArray)
                }
            }) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    if let error = error {
                        continuation.resume(throwing: PhotoLibraryError.albumCreationFailed(error.localizedDescription))
                    } else {
                        continuation.resume(throwing: PhotoLibraryError.albumCreationFailed("Unknown error"))
                    }
                }
            }
        }
    }

    /// 从指定相册移除照片（用于撤销 move 操作）
    /// - Parameters:
    ///   - localIdentifier: 照片 localIdentifier
    ///   - albumName: 相册名
    /// - Returns: 操作是否成功
    /// - Throws: PhotoLibraryError
    func removePhotoFromAlbum(withLocalIdentifier localIdentifier: String, albumName: String) async throws -> Bool {
        // 检查权限
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            // 资产已经不存在，视为已完成
            return true
        }

        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var targetCollection: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == albumName {
                targetCollection = collection
                stop.pointee = true
            }
        }

        guard let targetCollection else {
            // 相册不存在，视为无需回滚
            return true
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest(for: targetCollection)
                request?.removeAssets([asset] as NSArray)
            }) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else if let error {
                    continuation.resume(throwing: PhotoLibraryError.albumCreationFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: PhotoLibraryError.albumCreationFailed("Unknown error"))
                }
            }
        }
    }

}

// MARK: - 错误定义

extension PhotoLibraryService {
    /// PhotoKit操作相关错误
    enum PhotoLibraryError: Error, LocalizedError {
        case insufficientPermission
        case albumCreationFailed(String)
        case deletionFailed(String)
        case unknownError

        var errorDescription: String? {
            switch self {
            case .insufficientPermission:
                return "没有足够的相册权限，请在设置中授予应用相册访问权限"
            case .albumCreationFailed(let message):
                return "相册创建失败: \(message)"
            case .deletionFailed(let message):
                return "照片删除失败: \(message)"
            case .unknownError:
                return "未知错误"
            }
        }
    }
}
