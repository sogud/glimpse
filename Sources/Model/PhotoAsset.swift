import Photos
import SwiftUI
import Combine

/// PhotoAsset包装类，用于在SwiftUI中使用PHAsset
/// 由于PHAsset不是ObservableObject，我们需要创建一个包装器
class PhotoAsset: ObservableObject, Identifiable {
    let id = UUID()
    let asset: PHAsset

    // 缓存的图片数据
    @Published var image: UIImage?
    @Published var isLoading = false

    private var cancellables = Set<AnyCancellable>()

    init(asset: PHAsset) {
        self.asset = asset
    }

    /// 加载图片
    /// - Parameters:
    ///   - targetSize: 目标尺寸，默认使用较大尺寸以保持清晰度
    ///   - contentMode: 内容模式，默认使用aspectFit保持原图比例
    func loadImage(targetSize: CGSize = CGSize(width: 1200, height: 1200),
                  contentMode: PHImageContentMode = .aspectFit) {
        guard image == nil else { return }

        isLoading = true

        // 使用PHImageManager异步加载图片
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        // 使用fast模式避免强制缩放，保持原图质量
        options.resizeMode = .fast

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                self?.image = image
                self?.isLoading = false
            }
        }
    }

    /// 创建日期
    var creationDate: Date? {
        asset.creationDate
    }

    /// 文件大小（字节）
    var fileSize: Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first?.value(forKey: "fileSize") as? Int64
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

    /// 取消所有正在进行的请求
    deinit {
        cancellables.removeAll()
    }
}
