import Photos
import Foundation

/// 封装所有与系统相册交互的逻辑，供ViewModel调用
/// 不包含任何UI，不依赖第三方库
class PhotoLibraryService {

    /// 分页获取结果：`nextOffset` 表示下一次调用应使用的 offset（按扫描进度推进，而不是按返回数量）。
    struct PhotoFetchPage {
        let assets: [PHAsset]
        let nextOffset: Int
        let reachedEnd: Bool
    }

    // MARK: - 权限管理

    /// 相册权限状态
    enum AuthorizationStatus: Equatable {
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

    /// 根据清理场景获取候选照片。
    func fetchPhotos(
        preset: CleanupPreset,
        sourceAlbum: String? = nil,
        limit: Int = 50,
        offset: Int = 0,
        excludeAlbums: [String] = []
    ) throws -> [PHAsset] {
        try fetchPhotosPage(
            preset: preset,
            sourceAlbum: sourceAlbum,
            limit: limit,
            offset: offset,
            excludeAlbums: excludeAlbums
        ).assets
    }

    /// 根据清理场景分页获取候选照片（不会因为过滤导致 offset 卡住）。
    func fetchPhotosPage(
        preset: CleanupPreset,
        sourceAlbum: String? = nil,
        limit: Int = 50,
        offset: Int = 0,
        excludeAlbums: [String] = []
    ) throws -> PhotoFetchPage {
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        switch preset {
        case .advancedAlbum:
            return try fetchPhotosPage(fromAlbum: sourceAlbum, limit: limit, offset: offset, excludeAlbums: excludeAlbums)
        case .smartGroup:
            return PhotoFetchPage(assets: [], nextOffset: offset, reachedEnd: true)
        case .screenshots:
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(
                format: "mediaType == %d AND ((mediaSubtype & %d) != 0)",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            options.fetchLimit = limit + offset
            let excludedIdentifiers = excludedIdentifiers(for: excludeAlbums)
            let fetchResult = PHAsset.fetchAssets(with: options)
            return makePage(from: fetchResult, limit: limit, offset: offset, excludedIdentifiers: excludedIdentifiers)
        case .videos:
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            options.fetchLimit = limit + offset
            let excludedIdentifiers = excludedIdentifiers(for: excludeAlbums)
            let fetchResult = PHAsset.fetchAssets(with: options)
            return makePage(from: fetchResult, limit: limit, offset: offset, excludedIdentifiers: excludedIdentifiers)
        case .recentThirtyDays:
            let thresholdDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(
                format: "(mediaType == %d OR mediaType == %d) AND (creationDate >= %@)",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaType.video.rawValue,
                thresholdDate as NSDate
            )
            options.fetchLimit = limit + offset
            let excludedIdentifiers = excludedIdentifiers(for: excludeAlbums)
            let fetchResult = PHAsset.fetchAssets(with: options)
            return makePage(from: fetchResult, limit: limit, offset: offset, excludedIdentifiers: excludedIdentifiers)
        }
    }

    /// 获取照片PHAsset数组
    /// - Parameters:
    ///   - limit: 最大数量限制，默认为1000
    ///   - offset: 偏移量，用于分页获取，默认为 0
    ///   - excludeAlbums: 要排除的相册名称列表（已分类到这些相册的照片将被过滤掉）
    /// - Returns: PHAsset数组
    /// - Throws: PhotoLibraryError
    func fetchPhotos(limit: Int = 1000, offset: Int = 0, excludeAlbums: [String] = []) throws -> [PHAsset] {
        try fetchPhotosPage(limit: limit, offset: offset, excludeAlbums: excludeAlbums).assets
    }

    /// 获取照片分页（按扫描进度推进 offset）。
    func fetchPhotosPage(limit: Int = 1000, offset: Int = 0, excludeAlbums: [String] = []) throws -> PhotoFetchPage {
        // 检查权限
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        let excludedIdentifiers = excludedIdentifiers(for: excludeAlbums)

        // 创建获取选项
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 同时获取图片和视频
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.fetchLimit = limit + offset

        // 获取资产
        let fetchResult = PHAsset.fetchAssets(with: options)
        return makePage(from: fetchResult, limit: limit, offset: offset, excludedIdentifiers: excludedIdentifiers)
    }

    /// 按 localIdentifier 列表获取指定候选，保持传入顺序，供智能分组复核使用。
    func fetchPhotosPage(
        withLocalIdentifiers localIdentifiers: [String],
        limit: Int = 50,
        offset: Int = 0
    ) throws -> PhotoFetchPage {
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        let uniqueIdentifiers = localIdentifiers.reduce(into: [String]()) { result, identifier in
            guard !result.contains(identifier) else { return }
            result.append(identifier)
        }
        guard offset < uniqueIdentifiers.count else {
            return PhotoFetchPage(assets: [], nextOffset: uniqueIdentifiers.count, reachedEnd: true)
        }

        let pageIdentifiers = Array(uniqueIdentifiers.dropFirst(offset).prefix(limit))
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: pageIdentifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetsByIdentifier[asset.localIdentifier] = asset
        }

        let assets = pageIdentifiers.compactMap { assetsByIdentifier[$0] }
        let nextOffset = min(offset + pageIdentifiers.count, uniqueIdentifiers.count)
        return PhotoFetchPage(
            assets: assets,
            nextOffset: nextOffset,
            reachedEnd: nextOffset >= uniqueIdentifiers.count
        )
    }

    /// 从指定相册获取照片
    /// - Parameters:
    ///   - albumName: 相册名称，如果为nil则获取所有照片
    ///   - limit: 最大数量限制，默认为1000
    ///   - offset: 偏移量，用于分页获取，默认为 0
    ///   - excludeAlbums: 要排除的相册名称列表
    /// - Returns: PHAsset数组
    /// - Throws: PhotoLibraryError
    func fetchPhotos(fromAlbum albumName: String?, limit: Int = 1000, offset: Int = 0, excludeAlbums: [String] = []) throws -> [PHAsset] {
        try fetchPhotosPage(fromAlbum: albumName, limit: limit, offset: offset, excludeAlbums: excludeAlbums).assets
    }

    /// 从指定相册分页获取照片（按扫描进度推进 offset）。
    func fetchPhotosPage(fromAlbum albumName: String?, limit: Int = 1000, offset: Int = 0, excludeAlbums: [String] = []) throws -> PhotoFetchPage {
        // 如果没有指定相册，返回所有照片
        guard let albumName = albumName, !albumName.isEmpty else {
            return try fetchPhotosPage(limit: limit, offset: offset, excludeAlbums: excludeAlbums)
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
            return PhotoFetchPage(assets: [], nextOffset: offset, reachedEnd: true)
        }

        let excludedIdentifiers = excludedIdentifiers(for: excludeAlbums)

        // 创建获取选项
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 同时获取图片和视频
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.fetchLimit = limit + offset

        // 从指定相册获取资产
        let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        return makePage(from: fetchResult, limit: limit, offset: offset, excludedIdentifiers: excludedIdentifiers)
    }

    // MARK: - 删除照片

    // MARK: - Helpers

    private func excludedIdentifiers(for excludeAlbums: [String]) -> Set<String> {
        guard !excludeAlbums.isEmpty else { return [] }

        var excludedIdentifiers = Set<String>()
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            if let title = collection.localizedTitle, excludeAlbums.contains(title) {
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    excludedIdentifiers.insert(asset.localIdentifier)
                }
            }
        }
        return excludedIdentifiers
    }

    private func makePage(
        from fetchResult: PHFetchResult<PHAsset>,
        limit: Int,
        offset: Int,
        excludedIdentifiers: Set<String>
    ) -> PhotoFetchPage {
        var result: [PHAsset] = []
        var skipped = 0

        fetchResult.enumerateObjects { asset, _, stop in
            if skipped < offset {
                skipped += 1
                return
            }
            if !excludedIdentifiers.contains(asset.localIdentifier) {
                result.append(asset)
            }
            if result.count >= limit {
                stop.pointee = true
            }
        }

        let nextOffset = fetchResult.count
        let reachedEnd = fetchResult.count < (limit + offset)
        return PhotoFetchPage(assets: result, nextOffset: nextOffset, reachedEnd: reachedEnd)
    }

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

    /// 批量删除照片，只触发一次系统确认。
    /// - Parameter localIdentifiers: 要删除的照片 localIdentifier 集合
    /// - Returns: 操作是否成功
    /// - Throws: PhotoLibraryError
    func deletePhotos(withLocalIdentifiers localIdentifiers: [String]) async throws -> Bool {
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryError.insufficientPermission
        }

        let uniqueIdentifiers = Array(Set(localIdentifiers))
        guard !uniqueIdentifiers.isEmpty else {
            return true
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: uniqueIdentifiers, options: nil)
        var assetsToDelete: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assetsToDelete.append(asset)
        }

        guard !assetsToDelete.isEmpty else {
            return true
        }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else if let error {
                    continuation.resume(throwing: PhotoLibraryError.deletionFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: PhotoLibraryError.deletionFailed("Unknown error"))
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
