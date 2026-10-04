import AppKit
import Foundation
import Photos
import Vision

enum MacPhotoLibraryError: LocalizedError {
    case insufficientPermission
    case albumNotFound
    case imageUnavailable
    case partialApply(records: [PhotoAlbumMutationRecord], message: String)

    var errorDescription: String? {
        switch self {
        case .insufficientPermission:
            return "需要 Apple Photos 读写权限"
        case .albumNotFound:
            return "找不到选择的相册"
        case .imageUnavailable:
            return "无法从 Photos 读取这张图片"
        case .partialApply(_, let message):
            return "部分照片已经写入相册：\(message)"
        }
    }
}

@MainActor
final class MacPhotoLibraryService {
    private let imageManager = PHCachingImageManager()

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func accessiblePhotoCount() throws -> Int {
        try requireAuthorization()
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        return PHAsset.fetchAssets(with: options).count
    }

    func albums() throws -> [PhotoAlbumDescriptor] {
        try requireAuthorization()
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var albums: [PhotoAlbumDescriptor] = []
        collections.enumerateObjects { collection, _, _ in
            albums.append(
                PhotoAlbumDescriptor(
                    id: collection.localIdentifier,
                    name: collection.localizedTitle ?? "未命名相册",
                    assetCount: PHAsset.fetchAssets(in: collection, options: nil).count
                )
            )
        }
        return albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func assets(for source: PhotoClassificationSourceScope) throws -> [PHAsset] {
        try requireAuthorization()
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]

        let fetchResult: PHFetchResult<PHAsset>
        switch source {
        case .allPhotos:
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchResult = PHAsset.fetchAssets(with: options)
        case .album(let identifier, _):
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [identifier],
                options: nil
            )
            guard let collection = collections.firstObject else {
                throw MacPhotoLibraryError.albumNotFound
            }
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        case .dateRange(let start, let end):
            let calendar = Calendar.current
            let firstMoment = calendar.startOfDay(for: start)
            let endOfDay = calendar.date(
                byAdding: DateComponents(day: 1, second: -1),
                to: calendar.startOfDay(for: end)
            ) ?? end
            predicates.append(NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", firstMoment as NSDate, endOfDay as NSDate))
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchResult = PHAsset.fetchAssets(with: options)
        case .recentDays(let days):
            let start = Calendar.current.date(byAdding: .day, value: -max(days, 1), to: Date()) ?? .distantPast
            predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fetchResult = PHAsset.fetchAssets(with: options)
        }

        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func assets(localIdentifiers: [String]) -> [String: PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }
        return assets
    }

    func jpegData(for asset: PHAsset) async throws -> Data {
        let image = try await image(for: asset, longestEdge: 1024, networkAccessAllowed: true)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.82]
              ) else {
            throw MacPhotoLibraryError.imageUnavailable
        }
        return data
    }

    func thumbnail(for asset: PHAsset, longestEdge: CGFloat = 320) async throws -> NSImage {
        try await image(for: asset, longestEdge: longestEdge, networkAccessAllowed: true)
    }

    func recognizedText(for jpegData: Data) async -> String {
        guard let image = NSImage(data: jpegData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }

    func apply(_ additions: [PhotoAlbumAddition], onProgress: ([PhotoAlbumMutationRecord]) throws -> Void) async throws -> [PhotoAlbumMutationRecord] {
        var records: [PhotoAlbumMutationRecord] = []
        for (target, additionsForTarget) in Dictionary(grouping: additions, by: \.target) {
            do {
                let resolved = try await resolveAlbum(target)
                let collection = resolved.collection
                let existingAssets = PHAsset.fetchAssets(in: collection, options: nil)
                var existingIdentifiers = Set<String>()
                existingAssets.enumerateObjects { asset, _, _ in
                    existingIdentifiers.insert(asset.localIdentifier)
                }
                let assetIdentifiers = additionsForTarget.map(\.assetIdentifier).filter { !existingIdentifiers.contains($0) }
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIdentifiers, options: nil)
                guard assets.count > 0 else { continue }
                var addedIdentifiers: [String] = []
                assets.enumerateObjects { asset, _, _ in
                    addedIdentifiers.append(asset.localIdentifier)
                }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCollectionChangeRequest(for: collection)?.addAssets(assets)
                }
                records.append(contentsOf: addedIdentifiers.map {
                    PhotoAlbumMutationRecord(
                        assetIdentifier: $0,
                        albumIdentifier: collection.localIdentifier,
                        albumName: collection.localizedTitle ?? resolved.name,
                        albumWasCreatedByTask: resolved.wasCreated
                    )
                })
                try onProgress(records)
            } catch {
                if !records.isEmpty {
                    throw MacPhotoLibraryError.partialApply(records: records, message: error.localizedDescription)
                }
                throw error
            }
        }
        return records
    }

    func undo(_ records: [PhotoAlbumMutationRecord], deleteEmptyCreatedAlbums: Bool) async throws {
        for (albumIdentifier, recordsForAlbum) in Dictionary(grouping: records, by: \.albumIdentifier) {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumIdentifier], options: nil)
            guard let collection = collections.firstObject else { continue }
            let assets = PHAsset.fetchAssets(
                withLocalIdentifiers: recordsForAlbum.map(\.assetIdentifier),
                options: nil
            )
            if assets.count > 0 {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCollectionChangeRequest(for: collection)?.removeAssets(assets)
                }
            }
            if deleteEmptyCreatedAlbums,
               recordsForAlbum.contains(where: \.albumWasCreatedByTask),
               PHAsset.fetchAssets(in: collection, options: nil).count == 0 {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCollectionChangeRequest.deleteAssetCollections([collection] as NSArray)
                }
            }
        }
    }

    private func requireAuthorization() throws {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw MacPhotoLibraryError.insufficientPermission
        }
    }

    private func image(
        for asset: PHAsset,
        longestEdge: CGFloat,
        networkAccessAllowed: Bool
    ) async throws -> NSImage {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = networkAccessAllowed
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: longestEdge, height: longestEdge),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !finished else { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                finished = true
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: MacPhotoLibraryError.imageUnavailable)
                }
            }
        }
    }

    private func resolveAlbum(
        _ target: PhotoAlbumTarget
    ) async throws -> (collection: PHAssetCollection, name: String, wasCreated: Bool) {
        switch target {
        case .skip:
            throw MacPhotoLibraryError.albumNotFound
        case .existingAlbum(let identifier, let name):
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
            guard let collection = collections.firstObject else {
                throw MacPhotoLibraryError.albumNotFound
            }
            return (collection, name, false)
        case .newAlbum(let name):
            var placeholderIdentifier: String?
            try await PHPhotoLibrary.shared().performChanges {
                placeholderIdentifier = PHAssetCollectionChangeRequest
                    .creationRequestForAssetCollection(withTitle: name)
                    .placeholderForCreatedAssetCollection
                    .localIdentifier
            }
            guard let placeholderIdentifier,
                  let collection = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [placeholderIdentifier],
                    options: nil
                  ).firstObject else {
                throw MacPhotoLibraryError.albumNotFound
            }
            return (collection, name, true)
        }
    }
}
