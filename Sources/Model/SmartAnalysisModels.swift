import Foundation
import Photos
import SwiftUI
import Vision

/// 智能分析使用的媒体类型，避免把 PhotoKit 类型直接写入缓存。
enum SmartAnalysisMediaType: String, Codable, Hashable {
    case image
    case video
    case other

    init(assetMediaType: PHAssetMediaType) {
        switch assetMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        default:
            self = .other
        }
    }
}

/// Vision 分类标签，只保存标签和置信度，不保存照片内容。
struct SmartVisionLabel: Codable, Hashable, Identifiable {
    let identifier: String
    let confidence: Float

    var id: String { identifier }
}

/// 单张资源的 Vision 分析结果。
struct SmartVisionResult: Codable, Hashable {
    let didRunImageAnalysis: Bool
    let labels: [SmartVisionLabel]
    let recognizedTextLineCount: Int
    let recognizedTextCharacterCount: Int

    var hasMeaningfulText: Bool {
        recognizedTextLineCount >= 2 || recognizedTextCharacterCount >= 24
    }

    static let unavailable = SmartVisionResult(
        didRunImageAnalysis: false,
        labels: [],
        recognizedTextLineCount: 0,
        recognizedTextCharacterCount: 0
    )
}

/// 单个 PhotoKit 资源的本地分析缓存记录。
struct SmartAssetAnalysisRecord: Codable, Hashable, Identifiable {
    let localIdentifier: String
    let analyzerVersion: Int
    var visionAnalyzerVersion: Int?
    var analyzedAt: Date
    var visionAnalyzedAt: Date?
    let mediaType: SmartAnalysisMediaType
    let creationDate: Date?
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let isScreenshot: Bool
    let fileSizeBytes: Int64
    var visionResult: SmartVisionResult?
    var featureVector: [Float]?
    var sharpness: Double?
    var faceQuality: Double?
    var similarityGroupIdentifier: String?

    var id: String { localIdentifier }

    var isVideo: Bool {
        mediaType == .video
    }

    var hasCurrentVisionResult: Bool {
        visionAnalyzerVersion == SmartAnalysisConstants.visionAnalyzerVersion
    }
}

/// 一组相似照片及其本地质量推荐，删除仍需用户逐张复核。
struct SmartSimilarityCluster: Codable, Hashable, Identifiable {
    let id: String
    let memberIdentifiers: [String]
    let recommendedKeeperIdentifier: String
    let reviewIdentifiers: [String]
    let recoverableBytes: Int64
    let recommendationReasons: [String]
}

/// 智能洞察分组类型。
enum SmartInsightGroupKind: String, Codable, CaseIterable, Identifiable {
    case largeVideos
    case largeFiles
    case screenshots
    case documents
    case similarPhotos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeVideos:
            return "大视频"
        case .largeFiles:
            return "大文件"
        case .screenshots:
            return "截图"
        case .documents:
            return "文档文字"
        case .similarPhotos:
            return "相似照片"
        }
    }

    var subtitle: String {
        switch self {
        case .largeVideos:
            return "优先查看占空间的视频"
        case .largeFiles:
            return "按文件大小筛出的本地候选"
        case .screenshots:
            return "系统标记为截图的内容"
        case .documents:
            return "Vision 本地识别到较多文字"
        case .similarPhotos:
            return "Vision 特征发现可能重复"
        }
    }

    var iconName: String {
        switch self {
        case .largeVideos:
            return "video.fill"
        case .largeFiles:
            return "externaldrive.fill"
        case .screenshots:
            return "camera.viewfinder"
        case .documents:
            return "doc.text.viewfinder"
        case .similarPhotos:
            return "rectangle.stack.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .largeVideos:
            return .labelOrange
        case .largeFiles:
            return .brandPrimary
        case .screenshots:
            return .labelTeal
        case .documents:
            return .labelIndigo
        case .similarPhotos:
            return .swipeArchive
        }
    }
}

/// 可复核的智能洞察分组。
struct SmartInsightGroup: Codable, Hashable, Identifiable {
    let id: String
    let kind: SmartInsightGroupKind
    let title: String
    let subtitle: String
    let localIdentifiers: [String]
    let estimatedBytes: Int64
    let createdAt: Date
    let suggestedAlbumName: String?
    let similarityClusters: [SmartSimilarityCluster]

    init(
        id: String,
        kind: SmartInsightGroupKind,
        title: String,
        subtitle: String,
        localIdentifiers: [String],
        estimatedBytes: Int64,
        createdAt: Date,
        suggestedAlbumName: String?,
        similarityClusters: [SmartSimilarityCluster] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.localIdentifiers = localIdentifiers
        self.estimatedBytes = estimatedBytes
        self.createdAt = createdAt
        self.suggestedAlbumName = suggestedAlbumName
        self.similarityClusters = similarityClusters
    }

    var count: Int {
        localIdentifiers.count
    }

    var estimatedSizeText: String {
        guard estimatedBytes > 0 else { return "按需计算" }
        return ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
    }
}

/// 一次分析后的缓存快照。
struct SmartAnalysisSnapshot: Codable, Hashable {
    let analyzerVersion: Int
    let visionAnalyzerVersion: Int
    let scannedAt: Date
    let totalAssetCount: Int
    let recordsByIdentifier: [String: SmartAssetAnalysisRecord]
    let groups: [SmartInsightGroup]
}

/// 分析阶段。
enum SmartAnalysisPhase: String, Hashable {
    case metadata
    case vision
    case grouping
    case completed
}

/// 智能扫描进度。
struct SmartAnalysisProgress: Hashable {
    let phase: SmartAnalysisPhase
    let processed: Int
    let total: Int
    let message: String
    let groups: [SmartInsightGroup]

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(processed) / Double(total), 0), 1)
    }
}

enum SmartAnalysisConstants {
    static let analyzerVersion = 1
    static let visionAnalyzerVersion = 1
    static let largeVideoBytes: Int64 = 100 * 1024 * 1024
    static let largeFileBytes: Int64 = 25 * 1024 * 1024
    static let longVideoDuration: TimeInterval = 180
    static let visionLabelConfidence: VNConfidence = 0.35
    static let similarPhotoDistanceThreshold: Float = 0.18
}
