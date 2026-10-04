import Foundation

public struct PhotoLibraryAlbumResult: Codable, Equatable, Sendable {
    public let albumIdentifier: String
    public let addedAssetIdentifiers: [String]
    public let existingAssetIdentifiers: [String]
    public let missingAssetIdentifiers: [String]
}

public struct PhotoLibraryApplyReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, unknown, confirmed }
    public struct Album: Codable, Equatable, Sendable {
        public let addition: PhotoLibraryAlbumAddition
        public var status: Status
        public var result: PhotoLibraryAlbumResult?
    }

    public let plan: PhotoLibraryClassificationPlan
    public var albums: [Album]
    public var isComplete: Bool { albums.allSatisfy { $0.status == .confirmed } }
    public var confirmedAssetCount: Int {
        var count = 0
        for album in albums where album.status == .confirmed {
            if let result = album.result {
                count += result.addedAssetIdentifiers.count + result.existingAssetIdentifiers.count
            }
        }
        return count
    }

    func validate() throws {
        guard albums.map(\.addition) == (try plan.validatedAlbumAdditions()) else {
            throw PhotoLibraryCLIUsageError("回执相册与计划不一致")
        }
        for album in albums {
            guard album.status == .confirmed else {
                guard album.result == nil else { throw PhotoLibraryCLIUsageError("未确认回执含有成功结果") }
                continue
            }
            guard let result = album.result, !result.albumIdentifier.isEmpty else {
                throw PhotoLibraryCLIUsageError("已确认回执缺少相册结果")
            }
            let identifiers = result.addedAssetIdentifiers + result.existingAssetIdentifiers + result.missingAssetIdentifiers
            guard Set(identifiers).count == identifiers.count,
                  Set(identifiers) == Set(album.addition.assetIdentifiers) else {
                throw PhotoLibraryCLIUsageError("回执资源记录不完整或重复")
            }
        }
    }
}

extension PhotoLibraryWorkspace {
    public func receipts() throws -> [PhotoLibraryApplyReceipt] {
        try validateDirectory()
        let directory = directory.appendingPathComponent("Receipts", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.map {
            let receipt = try JSONDecoder().decode(PhotoLibraryApplyReceipt.self, from: Data(contentsOf: $0))
            try receipt.validate()
            return receipt
        }
    }

    public func apply(plan: PhotoLibraryClassificationPlan, photos: PhotosAutomation = PhotosAutomation()) throws -> PhotoLibraryApplyReceipt {
        let lease = try acquireLock()
        defer { withExtendedLifetime(lease) {} }
        let additions = try plan.validatedAlbumAdditions()
        let receiptDirectory = directory.appendingPathComponent("Receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: receiptDirectory, withIntermediateDirectories: true)
        let url = receiptDirectory.appendingPathComponent(plan.id.uuidString + ".json")
        var receipt: PhotoLibraryApplyReceipt
        if FileManager.default.fileExists(atPath: url.path) {
            receipt = try JSONDecoder().decode(PhotoLibraryApplyReceipt.self, from: Data(contentsOf: url))
            guard receipt.plan == plan else {
                throw PhotoLibraryCLIUsageError("计划或回执已被修改；请使用原始文件")
            }
            try receipt.validate()
        } else {
            receipt = PhotoLibraryApplyReceipt(plan: plan, albums: additions.map {
                PhotoLibraryApplyReceipt.Album(addition: $0, status: .pending, result: nil)
            })
        }
        for index in receipt.albums.indices where receipt.albums[index].status != .confirmed {
            receipt.albums[index].status = .unknown
            try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            do {
                receipt.albums[index].result = try photos.applyAlbum(receipt.albums[index].addition)
                receipt.albums[index].status = .confirmed
                try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                throw PhotoLibraryApplyError(confirmedCount: receipt.confirmedAssetCount,
                                            uncertainAlbumName: receipt.albums[index].addition.albumName,
                                            underlyingMessage: "回执：\(url.path)。\(error.localizedDescription)")
            }
        }
        return receipt
    }
}
