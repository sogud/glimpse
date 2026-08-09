import Foundation
import Photos
import Vision
#if canImport(UIKit)
import UIKit
#endif

typealias SmartAnalysisProgressHandler = (SmartAnalysisProgress) async -> Void

/// 本地智能分析服务：只读取 PhotoKit 和 Vision 结果，不上传照片，不修改相册。
@MainActor
final class SmartPhotoAnalysisService {
    private let photoLibraryService: PhotoLibraryService
    private let store: SmartPhotoAnalysisStore
    private let imageManager = PHCachingImageManager()
    private let libraryChangeObserver = SmartPhotoLibraryChangeObserver()
    var onPhotoLibraryChange: (() -> Void)?

    init(
        photoLibraryService: PhotoLibraryService = PhotoLibraryService(),
        store: SmartPhotoAnalysisStore? = nil
    ) {
        self.photoLibraryService = photoLibraryService
        self.store = store ?? .shared
        libraryChangeObserver.setOnChange { [weak self] in
            Task { @MainActor in
                self?.onPhotoLibraryChange?()
            }
        }
        PHPhotoLibrary.shared().register(libraryChangeObserver)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(libraryChangeObserver)
    }

    func currentAuthorizationStatus() -> PhotoLibraryService.AuthorizationStatus {
        photoLibraryService.currentAuthorizationStatus()
    }

    func requestAuthorization() async -> PhotoLibraryService.AuthorizationStatus {
        await photoLibraryService.requestAuthorization()
    }

    func loadCachedSnapshot() -> SmartAnalysisSnapshot? {
        do {
            guard let snapshot = try store.loadSnapshot() else { return nil }
            guard snapshot.analyzerVersion == SmartAnalysisConstants.analyzerVersion else { return nil }
            return snapshot
        } catch {
            return nil
        }
    }

    func analyzeLocalPhotoLibrary(progress: @escaping SmartAnalysisProgressHandler) async throws -> SmartAnalysisSnapshot {
        guard currentAuthorizationStatus() == .authorized || currentAuthorizationStatus() == .limited else {
            throw PhotoLibraryService.PhotoLibraryError.insufficientPermission
        }

        let assets = fetchAccessibleAssets()
        let cachedSnapshot = loadCachedSnapshot()
        let currentFingerprints = assets.map {
            AssetFingerprint(
                id: $0.localIdentifier,
                modificationDate: $0.modificationDate,
                analyzerVersion: SmartAnalysisConstants.analyzerVersion
            )
        }
        let cachedFingerprints = cachedSnapshot?.recordsByIdentifier.values.map {
            AssetFingerprint(
                id: $0.localIdentifier,
                modificationDate: $0.modificationDate,
                analyzerVersion: $0.analyzerVersion
            )
        } ?? []
        let plan = IncrementalAnalysisPlanner.plan(cached: cachedFingerprints, current: currentFingerprints)
        var recordsByIdentifier = cachedSnapshot?.recordsByIdentifier ?? [:]
        plan.deletedIdentifiers.forEach { recordsByIdentifier.removeValue(forKey: $0) }
        let identifiersRequiringAnalysis = Set(plan.identifiersRequiringAnalysis)
        let cachedGroups = cachedSnapshot?.groups ?? []

        if identifiersRequiringAnalysis.isEmpty,
           plan.deletedIdentifiers.isEmpty,
           let cachedSnapshot {
            let refreshedSnapshot = SmartAnalysisSnapshot(
                analyzerVersion: cachedSnapshot.analyzerVersion,
                visionAnalyzerVersion: cachedSnapshot.visionAnalyzerVersion,
                scannedAt: Date(),
                totalAssetCount: assets.count,
                recordsByIdentifier: cachedSnapshot.recordsByIdentifier,
                groups: cachedSnapshot.groups
            )
            try store.saveSnapshot(refreshedSnapshot)
            await progress(SmartAnalysisProgress(
                phase: .completed,
                processed: assets.count,
                total: assets.count,
                message: "照片库没有变化",
                groups: cachedSnapshot.groups
            ))
            return refreshedSnapshot
        }

        var processedMetadata = 0
        for asset in assets {
            try Task.checkCancellation()

            if identifiersRequiringAnalysis.contains(asset.localIdentifier) {
                recordsByIdentifier[asset.localIdentifier] = makeMetadataRecord(for: asset)
            }

            processedMetadata += 1
            if processedMetadata == assets.count || processedMetadata % 24 == 0 {
                await progress(
                    SmartAnalysisProgress(
                        phase: .metadata,
                        processed: processedMetadata,
                        total: assets.count,
                        message: "正在读取本地元数据",
                        groups: cachedGroups
                    )
                )
                await Task.yield()
            }
        }

        let metadataGroups = makeInsightGroups(from: recordsByIdentifier)
        try saveSnapshot(
            recordsByIdentifier: recordsByIdentifier,
            groups: metadataGroups,
            totalAssetCount: assets.count
        )

        let imageAssetsForVision = assets.filter { asset in
            guard asset.mediaType == .image else { return false }
            guard let record = recordsByIdentifier[asset.localIdentifier] else { return true }
            return identifiersRequiringAnalysis.contains(asset.localIdentifier)
                || !record.hasCurrentVisionResult
                || record.featureVector == nil
        }

        var processedVision = 0

        for asset in imageAssetsForVision {
            try Task.checkCancellation()

            var record = recordsByIdentifier[asset.localIdentifier] ?? makeMetadataRecord(for: asset)
            record.similarityGroupIdentifier = nil

            if let cgImage = await requestAnalysisImage(for: asset) {
                let result = await Task.detached(priority: .utility) {
                    Self.analyzeImage(cgImage)
                }.value
                record.visionResult = result.vision
                record.visionAnalyzerVersion = SmartAnalysisConstants.visionAnalyzerVersion
                record.visionAnalyzedAt = Date()
                record.featureVector = result.featureVector
                record.sharpness = result.sharpness
                record.faceQuality = result.faceQuality
            } else {
                record.visionResult = .unavailable
                record.visionAnalyzerVersion = SmartAnalysisConstants.visionAnalyzerVersion
                record.visionAnalyzedAt = Date()
            }

            recordsByIdentifier[asset.localIdentifier] = record
            processedVision += 1

            if processedVision == imageAssetsForVision.count || processedVision % 8 == 0 {
                await progress(
                    SmartAnalysisProgress(
                        phase: .vision,
                        processed: processedVision,
                        total: max(imageAssetsForVision.count, 1),
                        message: "正在执行本地 Vision 分析",
                        groups: metadataGroups
                    )
                )
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        await progress(
            SmartAnalysisProgress(
                phase: .grouping,
                processed: 1,
                total: 1,
                message: "正在生成洞察分组",
                groups: makeInsightGroups(from: recordsByIdentifier)
            )
        )

        let finalGroups = makeInsightGroups(from: recordsByIdentifier)
        let finalSnapshot = try saveSnapshot(
            recordsByIdentifier: recordsByIdentifier,
            groups: finalGroups,
            totalAssetCount: assets.count
        )

        await progress(
            SmartAnalysisProgress(
                phase: .completed,
                processed: assets.count,
                total: assets.count,
                message: "分析完成",
                groups: finalGroups
            )
        )

        return finalSnapshot
    }

    private func fetchAccessibleAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )

        let fetchResult = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    private func makeMetadataRecord(for asset: PHAsset) -> SmartAssetAnalysisRecord {
        SmartAssetAnalysisRecord(
            localIdentifier: asset.localIdentifier,
            analyzerVersion: SmartAnalysisConstants.analyzerVersion,
            visionAnalyzerVersion: nil,
            analyzedAt: Date(),
            visionAnalyzedAt: nil,
            mediaType: SmartAnalysisMediaType(assetMediaType: asset.mediaType),
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            isScreenshot: isScreenshot(asset),
            fileSizeBytes: estimatedFileSize(for: asset),
            visionResult: nil,
            featureVector: nil,
            sharpness: nil,
            faceQuality: nil,
            similarityGroupIdentifier: nil
        )
    }

    private func isScreenshot(_ asset: PHAsset) -> Bool {
        asset.mediaSubtypes.rawValue & PHAssetMediaSubtype.photoScreenshot.rawValue != 0
    }

    private func estimatedFileSize(for asset: PHAsset) -> Int64 {
        // iOS 18 没有公开的同步资源大小接口，避免为全库扫描下载 iCloud 原件。
        return 0
    }

    private func requestAnalysisImage(for asset: PHAsset) async -> CGImage? {
        #if canImport(UIKit)
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.version = .current
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            var didResume = false

            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 900, height: 900),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !didResume else { return }

                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let hasError = info?[PHImageErrorKey] != nil

                if isCancelled || hasError {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                guard !isDegraded else { return }

                didResume = true
                continuation.resume(returning: image?.cgImage)
            }
        }
        #else
        return nil
        #endif
    }

    nonisolated private static func analyzeImage(
        _ cgImage: CGImage
    ) -> (vision: SmartVisionResult, featureVector: [Float]?, sharpness: Double, faceQuality: Double?) {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        let classifyRequest = VNClassifyImageRequest()
        let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
        let faceQualityRequest = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([textRequest, classifyRequest, featurePrintRequest, faceQualityRequest])
        } catch {
            return (.unavailable, nil, 0, nil)
        }

        let recognizedTexts = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first }
            .filter { candidate in
                candidate.confidence >= 0.45 &&
                !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        let characterCount = recognizedTexts.reduce(0) { partialResult, text in
            partialResult + text.string.count
        }

        let labels = (classifyRequest.results ?? [])
            .filter { $0.confidence >= SmartAnalysisConstants.visionLabelConfidence }
            .prefix(6)
            .map { observation in
                SmartVisionLabel(identifier: observation.identifier, confidence: observation.confidence)
            }

        let vision = SmartVisionResult(
            didRunImageAnalysis: true,
            labels: labels,
            recognizedTextLineCount: recognizedTexts.count,
            recognizedTextCharacterCount: characterCount
        )

        let featureVector = featurePrintRequest.results?.first?.data.withUnsafeBytes {
            Array($0.bindMemory(to: Float.self))
        }
        let faceQuality = faceQualityRequest.results?
            .compactMap(\.faceCaptureQuality)
            .map(Double.init)
            .max()

        return (vision, featureVector, sharpnessScore(cgImage), faceQuality)
    }

    nonisolated private static func sharpnessScore(_ image: CGImage) -> Double {
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var gradientTotal = 0.0
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let index = y * width + x
                gradientTotal += abs(Double(pixels[index]) - Double(pixels[index + 1]))
                gradientTotal += abs(Double(pixels[index]) - Double(pixels[index + width]))
            }
        }
        let maximum = Double((width - 1) * (height - 1) * 2 * 255)
        return min(max(gradientTotal / maximum * 8, 0), 1)
    }

    private func makeInsightGroups(from recordsByIdentifier: [String: SmartAssetAnalysisRecord]) -> [SmartInsightGroup] {
        let records = Array(recordsByIdentifier.values)
        let similarityClusters = makeSimilarityClusters(from: records)

        let largeVideos = records.filter { record in
            record.mediaType == .video &&
            (record.fileSizeBytes >= SmartAnalysisConstants.largeVideoBytes || record.duration >= SmartAnalysisConstants.longVideoDuration)
        }

        let largeFiles = records.filter { record in
            record.fileSizeBytes >= SmartAnalysisConstants.largeFileBytes
        }

        let screenshots = records.filter(\.isScreenshot)

        let documents = records.filter { record in
            record.visionResult?.hasMeaningfulText == true
        }

        let similarIdentifiers = similarityClusters.flatMap(\.memberIdentifiers)

        return [
            makeGroup(kind: .largeVideos, records: largeVideos, suggestedAlbumName: nil),
            makeGroup(kind: .largeFiles, records: largeFiles, suggestedAlbumName: nil),
            makeGroup(kind: .screenshots, records: screenshots, suggestedAlbumName: "PhotoSort 截图"),
            makeGroup(kind: .documents, records: documents, suggestedAlbumName: "PhotoSort 文档"),
            makeGroup(
                kind: .similarPhotos,
                records: similarIdentifiers.compactMap { recordsByIdentifier[$0] },
                suggestedAlbumName: nil,
                similarityClusters: similarityClusters
            )
        ]
        .compactMap { $0 }
    }

    private func makeGroup(
        kind: SmartInsightGroupKind,
        records: [SmartAssetAnalysisRecord],
        suggestedAlbumName: String?,
        similarityClusters: [SmartSimilarityCluster] = []
    ) -> SmartInsightGroup? {
        guard !records.isEmpty else { return nil }

        let sortedRecords = records.sorted { left, right in
            if left.fileSizeBytes != right.fileSizeBytes {
                return left.fileSizeBytes > right.fileSizeBytes
            }
            return (left.creationDate ?? .distantPast) > (right.creationDate ?? .distantPast)
        }

        return SmartInsightGroup(
            id: kind.rawValue,
            kind: kind,
            title: kind.title,
            subtitle: kind.subtitle,
            localIdentifiers: sortedRecords.map(\.localIdentifier),
            estimatedBytes: sortedRecords.reduce(0) { $0 + max($1.fileSizeBytes, 0) },
            createdAt: Date(),
            suggestedAlbumName: suggestedAlbumName,
            similarityClusters: similarityClusters
        )
    }

    private func makeSimilarityClusters(
        from records: [SmartAssetAnalysisRecord]
    ) -> [SmartSimilarityCluster] {
        let candidates = records.compactMap { record -> SimilarityCandidate? in
            guard record.mediaType == .image,
                  let featureVector = record.featureVector,
                  !featureVector.isEmpty else { return nil }
            return SimilarityCandidate(
                id: record.localIdentifier,
                capturedAt: record.creationDate ?? record.analyzedAt,
                pixelWidth: record.pixelWidth,
                pixelHeight: record.pixelHeight,
                featureVector: featureVector,
                sharpness: record.sharpness ?? 0,
                faceQuality: record.faceQuality,
                estimatedBytes: record.fileSizeBytes
            )
        }

        return SimilarityClusterer(
            maximumFeatureDistance: SmartAnalysisConstants.similarPhotoDistanceThreshold
        )
        .clusters(from: candidates)
        .map {
            SmartSimilarityCluster(
                id: $0.id,
                memberIdentifiers: $0.memberIdentifiers,
                recommendedKeeperIdentifier: $0.recommendedKeeperIdentifier,
                reviewIdentifiers: $0.reviewIdentifiers,
                recoverableBytes: $0.recoverableBytes,
                recommendationReasons: $0.recommendationReasons
            )
        }
    }

    @discardableResult
    private func saveSnapshot(
        recordsByIdentifier: [String: SmartAssetAnalysisRecord],
        groups: [SmartInsightGroup],
        totalAssetCount: Int
    ) throws -> SmartAnalysisSnapshot {
        let snapshot = SmartAnalysisSnapshot(
            analyzerVersion: SmartAnalysisConstants.analyzerVersion,
            visionAnalyzerVersion: SmartAnalysisConstants.visionAnalyzerVersion,
            scannedAt: Date(),
            totalAssetCount: totalAssetCount,
            recordsByIdentifier: recordsByIdentifier,
            groups: groups
        )
        try store.saveSnapshot(snapshot)
        return snapshot
    }
}

private final class SmartPhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var onChange: (() -> Void)?

    func setOnChange(_ callback: @escaping () -> Void) {
        lock.withLock {
            onChange = callback
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        let callback = lock.withLock { onChange }
        callback?()
    }
}
