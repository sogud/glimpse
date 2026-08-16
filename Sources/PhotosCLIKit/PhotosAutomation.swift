import Foundation

public struct ExportedPhotoBatch: Sendable {
    public let photos: [SelectedPhoto]
    public let skippedAssetIdentifiers: Set<String>
    public let temporaryDirectory: URL

    public func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

public struct PhotosAutomation: Sendable {
    public static let maximumExportCount = 10

    public init() {}

    public func exportSelection(limit: Int) throws -> ExportedPhotoBatch {
        try export(
            limit: limit,
            script: Self.exportSelectionScript,
            additionalArguments: [],
            allowsEmptyResult: false
        )
    }

    public func exportLibraryBatch(
        excluding processedAssetIdentifiers: Set<String>,
        limit: Int
    ) throws -> ExportedPhotoBatch {
        return try export(
            limit: limit,
            script: Self.exportNextItemsScript,
            additionalArguments: processedAssetIdentifiers.sorted(),
            allowsEmptyResult: true
        )
    }

    private func export(
        limit: Int,
        script: String,
        additionalArguments: [String],
        allowsEmptyResult: Bool
    ) throws -> ExportedPhotoBatch {
        let boundedLimit = min(max(limit, 1), Self.maximumExportCount)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glimpse-photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<boundedLimit {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(String(index), isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        do {
            let data = try CommandRunner.run(
                "/usr/bin/osascript",
                arguments: ["-e", script, root.path, String(boundedLimit)] + additionalArguments
            )
            let metadata = String(decoding: data, as: UTF8.self)
            let photos = try parseExportedPhotos(metadata, root: root)
            guard allowsEmptyResult || !photos.isEmpty else {
                throw GlimpsePhotosCLIError.noExportedPhotos
            }
            return ExportedPhotoBatch(
                photos: photos,
                skippedAssetIdentifiers: skippedIdentifiers(
                    metadata: metadata,
                    exportedPhotos: photos
                ),
                temporaryDirectory: root
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    public func apply(_ additions: [PhotoLibraryAlbumAddition]) throws -> Int {
        var appliedCount = 0
        for addition in additions where !addition.assetIdentifiers.isEmpty {
            let data = try CommandRunner.run(
                "/usr/bin/osascript",
                arguments: ["-e", Self.applyScript, addition.folderName, addition.albumName] + addition.assetIdentifiers
            )
            appliedCount += Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return appliedCount
    }

    private func parseExportedPhotos(_ metadata: String, root: URL) throws -> [SelectedPhoto] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"])
        return try metadata.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5,
                  let width = Int(fields[2]),
                  let height = Int(fields[3]),
                  let index = Int(fields[4]) else {
                return nil
            }
            let exportDirectory = root.appendingPathComponent(String(index), isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: exportDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            guard let exportedURL = files.first(where: {
                imageExtensions.contains($0.pathExtension.lowercased())
            }) else {
                return nil
            }
            return SelectedPhoto(
                identifier: fields[0],
                filename: fields[1],
                width: width,
                height: height,
                exportedURL: exportedURL
            )
        }
    }

    private func skippedIdentifiers(
        metadata: String,
        exportedPhotos: [SelectedPhoto]
    ) -> Set<String> {
        let attempted = Set(metadata.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init)
        })
        return attempted.subtracting(exportedPhotos.map(\.identifier))
    }

    private static let exportHandler = #"""
    on exportItems(chosenItems, exportRoot, maximumCount)
        set outputText to ""
        set currentIndex to 0
        repeat with photoItem in chosenItems
            if currentIndex is greater than or equal to maximumCount then exit repeat
            set destinationFolder to POSIX file (exportRoot & "/" & (currentIndex as text))
            tell application "Photos"
                export {photoItem} to destinationFolder using originals false
                set outputText to outputText & (id of photoItem as text) & tab & (filename of photoItem as text) & tab & (width of photoItem as text) & tab & (height of photoItem as text) & tab & (currentIndex as text) & linefeed
            end tell
            set currentIndex to currentIndex + 1
        end repeat
        return outputText
    end exportItems
    """#

    private static let exportSelectionScript = exportHandler + "\n" + #"""
    on run argv
        set exportRoot to item 1 of argv
        set maximumCount to item 2 of argv as integer
        tell application "Photos"
            set chosenItems to selection
            if (count of chosenItems) is 0 then error "请先在照片 App 中选择照片"
        end tell
        return exportItems(chosenItems, exportRoot, maximumCount)
    end run
    """#

    private static let exportNextItemsScript = exportHandler + "\n" + #"""
    on run argv
        set exportRoot to item 1 of argv
        set maximumCount to item 2 of argv as integer
        if (count of argv) > 2 then
            set processedIDs to items 3 thru -1 of argv
        else
            set processedIDs to {}
        end if
        set chosenItems to {}
        tell application "Photos"
            repeat with photoItem in media items
                set assetID to id of photoItem as text
                if assetID is not in processedIDs then set end of chosenItems to photoItem
                if (count of chosenItems) is greater than or equal to maximumCount then exit repeat
            end repeat
        end tell
        return exportItems(chosenItems, exportRoot, maximumCount)
    end run
    """#

    private static let applyScript = #"""
    on run argv
        set folderName to item 1 of argv
        set albumName to item 2 of argv
        set assetIDs to items 3 thru -1 of argv
        tell application "Photos"
            set selectedMediaItems to {}
            repeat with assetID in assetIDs
                set matchingItems to every media item whose id is assetID
                if (count of matchingItems) is greater than 0 then set end of selectedMediaItems to item 1 of matchingItems
            end repeat
            if (count of selectedMediaItems) is 0 then return 0

            set matchingFolders to every folder whose name is folderName
            if (count of matchingFolders) is 0 then
                set targetFolder to make new folder named folderName
            else
                set targetFolder to item 1 of matchingFolders
            end if
            set matchingAlbums to every album of targetFolder whose name is albumName
            if (count of matchingAlbums) is 0 then
                set targetAlbum to make new album named albumName at targetFolder
            else
                set targetAlbum to item 1 of matchingAlbums
            end if
            add selectedMediaItems to targetAlbum
            return count of selectedMediaItems
        end tell
    end run
    """#
}
