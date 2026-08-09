import Foundation
import Photos
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

enum OriginalFileSizeState: Equatable {
    case idle
    case loadingRemote
    case ready(Int64)
    case failed
}

/// PhotoAsset包装类，用于在SwiftUI中使用PHAsset
/// 由于PHAsset不是ObservableObject，我们需要创建一个包装器
class PhotoAsset: ObservableObject, Identifiable {
    private static let imageManager = PHCachingImageManager()
    private static let resourceManager = PHAssetResourceManager.default()
    private static let fileSizeCache = NSCache<NSString, NSNumber>()

    let id: String
    let asset: PHAsset

    // 缓存的图片数据
    @Published var image: PlatformImage?
    @Published var isLoading = false
    @Published private(set) var originalFileSizeState: OriginalFileSizeState = .idle

    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var requestedTargetSize: CGSize = .zero
    private var loadedTargetSize: CGSize = .zero
    private var fileSizeLoader: ResourceSizeLoader?

    init(asset: PHAsset) {
        self.asset = asset
        self.id = asset.localIdentifier
    }

    /// 加载图片
    /// - Parameters:
    ///   - targetSize: 目标尺寸，默认使用当前设备显示尺寸
    ///   - contentMode: 内容模式，默认使用aspectFit保持原图比例
    func loadImage(
        targetSize: CGSize = PhotoAsset.defaultTargetSize,
        contentMode: PHImageContentMode = .aspectFit
    ) {
        let normalizedTargetSize = Self.normalizedTargetSize(targetSize)
        guard shouldRequestImage(for: normalizedTargetSize) else { return }

        isLoading = true

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        if requestID != PHInvalidImageRequestID {
            Self.imageManager.cancelImageRequest(requestID)
        }

        requestedTargetSize = normalizedTargetSize

        requestID = Self.imageManager.requestImage(
            for: asset,
            targetSize: normalizedTargetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, info in
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if isCancelled { return }

            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

            DispatchQueue.main.async {
                if let image {
                    self?.image = image
                }

                guard let self else { return }
                if !isDegraded {
                    self.loadedTargetSize = normalizedTargetSize
                    self.isLoading = false
                    self.requestID = PHInvalidImageRequestID
                }
            }
        }
    }

    private func shouldRequestImage(for targetSize: CGSize) -> Bool {
        if isLoading {
            return targetSize.width > requestedTargetSize.width || targetSize.height > requestedTargetSize.height
        }

        guard image != nil else { return true }

        // 仅在需要明显更高分辨率时才重新请求，避免轻微布局变化导致重复解码。
        return targetSize.width > loadedTargetSize.width * 1.2 || targetSize.height > loadedTargetSize.height * 1.2
    }

    private static var defaultTargetSize: CGSize {
        #if canImport(UIKit)
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds
        return normalizedTargetSize(
            CGSize(width: bounds.width * scale, height: bounds.height * scale)
        )
        #elseif canImport(AppKit)
        return normalizedTargetSize(CGSize(width: 1440, height: 1440))
        #endif
    }

    private static func normalizedTargetSize(_ size: CGSize) -> CGSize {
        let maxDimension: CGFloat = 1800
        let width = min(max(1, size.width.rounded(.up)), maxDimension)
        let height = min(max(1, size.height.rounded(.up)), maxDimension)
        return CGSize(width: width, height: height)
    }

    /// 创建日期
    var creationDate: Date? {
        asset.creationDate
    }

    /// 文件大小（字节）
    var fileSize: Int64? {
        if case .ready(let bytes) = originalFileSizeState {
            return bytes
        }
        if let cached = Self.cachedFileSize(for: id) {
            return cached
        }
        return nil
    }

    /// 格式化后的文件大小字符串
    var fileSizeString: String {
        guard let size = fileSize else { return "未知大小" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// 是否为视频
    var isVideo: Bool {
        asset.mediaType == .video
    }

    /// 视频时长（如果是视频）
    var videoDuration: String? {
        guard asset.mediaType == .video else { return nil }
        let duration = Int(asset.duration)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func loadOriginalFileSize() {
        if case .ready = originalFileSizeState {
            return
        }

        if let cached = Self.cachedFileSize(for: id) {
            originalFileSizeState = .ready(cached)
            return
        }

        guard let resource = preferredOriginalResource else {
            originalFileSizeState = .failed
            return
        }

        cancelOriginalFileSizeLoad(resetState: false)

        originalFileSizeState = .loadingRemote

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let source = PhotoAssetResourceDataSource(
            resource: resource,
            options: options,
            manager: Self.resourceManager
        )
        let loader = ResourceSizeLoader(source: source)
        fileSizeLoader = loader
        loader.load { [weak self, weak loader] result in
            DispatchQueue.main.async {
                guard let self, let loader, self.fileSizeLoader === loader else { return }
                self.fileSizeLoader = nil

                if case .success(let resolvedSize) = result, resolvedSize > 0 {
                    Self.cache(fileSize: resolvedSize, for: self.id)
                    self.originalFileSizeState = .ready(resolvedSize)
                } else {
                    self.originalFileSizeState = .failed
                }
            }
        }
    }

    func cancelOriginalFileSizeLoad(resetState: Bool = true) {
        fileSizeLoader?.cancel()
        fileSizeLoader = nil

        if resetState, case .loadingRemote = originalFileSizeState {
            originalFileSizeState = .idle
        }
    }

    private var preferredOriginalResource: PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)

        if asset.mediaType == .video {
            return firstResource(in: resources, matching: [.fullSizeVideo, .video])
        }

        return firstResource(in: resources, matching: [.fullSizePhoto, .photo, .alternatePhoto])
    }

    private func firstResource(
        in resources: [PHAssetResource],
        matching preferredTypes: [PHAssetResourceType]
    ) -> PHAssetResource? {
        for type in preferredTypes {
            if let resource = resources.first(where: { $0.type == type }) {
                return resource
            }
        }
        return resources.first
    }

    private static func cachedFileSize(for identifier: String) -> Int64? {
        fileSizeCache.object(forKey: identifier as NSString)?.int64Value
    }

    private static func cache(fileSize: Int64, for identifier: String) {
        fileSizeCache.setObject(NSNumber(value: fileSize), forKey: identifier as NSString)
    }

    /// 取消所有正在进行的请求
    deinit {
        if requestID != PHInvalidImageRequestID {
            Self.imageManager.cancelImageRequest(requestID)
        }
        cancelOriginalFileSizeLoad(resetState: false)
    }
}

private final class PhotoAssetResourceDataSource: ResourceDataSource {
    private let resource: PHAssetResource
    private let options: PHAssetResourceRequestOptions
    private let manager: PHAssetResourceManager

    init(
        resource: PHAssetResource,
        options: PHAssetResourceRequestOptions,
        manager: PHAssetResourceManager
    ) {
        self.resource = resource
        self.options = options
        self.manager = manager
    }

    func requestData(
        received: @escaping (Data) -> Void,
        completion: @escaping (Error?) -> Void
    ) -> Int32 {
        manager.requestData(
            for: resource,
            options: options,
            dataReceivedHandler: received,
            completionHandler: completion
        )
    }

    func cancel(requestID: Int32) {
        manager.cancelDataRequest(requestID)
    }
}
