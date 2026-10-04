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
    private let runCommand: @Sendable (String, [String]) throws -> Data

    public init() {
        runCommand = { try CommandRunner.run($0, arguments: $1) }
    }

    public init(runCommand: @escaping @Sendable (String, [String]) throws -> Data) {
        self.runCommand = runCommand
    }

    public func exportSelection(limit: Int) throws -> ExportedPhotoBatch {
        try export(
            limit: limit,
            script: Self.exportSelectionScript,
            excludedIdentifiers: nil,
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
            excludedIdentifiers: processedAssetIdentifiers,
            allowsEmptyResult: true
        )
    }

    private func export(
        limit: Int,
        script: String,
        excludedIdentifiers: Set<String>?,
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
            var arguments = ["-e", script, root.path, String(boundedLimit)]
            if let excludedIdentifiers {
                let identifiersURL = root.appendingPathComponent("excluded.txt")
                try Data(excludedIdentifiers.sorted().joined(separator: "\n").utf8).write(to: identifiersURL)
                arguments.append(identifiersURL.path)
            }
            let data = try runCommand(
                "/usr/bin/osascript",
                arguments
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

    public func applyAlbum(_ addition: PhotoLibraryAlbumAddition) throws -> PhotoLibraryAlbumResult {
        let data = try runCommand("/usr/bin/osascript", ["-e", Self.applyScript, addition.folderName, addition.albumName] + addition.assetIdentifiers)
        var albumIdentifier: String?
        var added: [String] = []
        var existing: [String] = []
        var missing: [String] = []
        var seen: Set<String> = []
        let expected = Set(addition.assetIdentifiers)
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2 else { throw GlimpsePhotosCLIError.invalidResponse }
            if fields[0] == "album" {
                guard albumIdentifier == nil, !fields[1].isEmpty else { throw GlimpsePhotosCLIError.invalidResponse }
                albumIdentifier = fields[1]
                continue
            }
            guard expected.contains(fields[1]), seen.insert(fields[1]).inserted else { throw GlimpsePhotosCLIError.invalidResponse }
            switch fields[0] {
            case "added": added.append(fields[1])
            case "existing": existing.append(fields[1])
            case "missing": missing.append(fields[1])
            default: throw GlimpsePhotosCLIError.invalidResponse
            }
        }
        guard let albumIdentifier, seen == expected else { throw GlimpsePhotosCLIError.invalidResponse }
        return PhotoLibraryAlbumResult(albumIdentifier: albumIdentifier, addedAssetIdentifiers: added,
                                       existingAssetIdentifiers: existing, missingAssetIdentifiers: missing)
    }

    private func parseExportedPhotos(_ metadata: String, root: URL) throws -> [SelectedPhoto] {
        let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"])
        return try metadata.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, !fields[0].isEmpty,
                  let width = Int(fields[1]),
                  let height = Int(fields[2]),
                  let index = Int(fields[3]), index >= 0, index < Self.maximumExportCount else {
                throw GlimpsePhotosCLIError.invalidResponse
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
                filename: exportedURL.lastPathComponent,
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
                set outputText to outputText & (id of photoItem as text) & tab & (width of photoItem as text) & tab & (height of photoItem as text) & tab & (currentIndex as text) & linefeed
                try
                    export {photoItem} to destinationFolder using originals false
                end try
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

    private static let exportNextItemsScript = #"""
    use framework "Foundation"
    use scripting additions
    on excludedIDs(processedText)
        return current application's NSSet's setWithArray:(paragraphs of processedText)
    end excludedIDs
    """# + "\n" + exportHandler + "\n" + #"""
    on run argv
        set exportRoot to item 1 of argv
        set maximumCount to item 2 of argv as integer
        set excludedFile to POSIX file (item 3 of argv)
        set processedText to read excludedFile as «class utf8»
        set processedIDs to my excludedIDs(processedText)
        set chosenItems to {}
        tell application "Photos" to set libraryIDs to id of every media item
        repeat with libraryID in libraryIDs
            set assetID to libraryID as text
            if not ((processedIDs's containsObject:assetID) as boolean) then
                tell application "Photos" to set end of chosenItems to first media item whose id is assetID
            end if
            if (count of chosenItems) is greater than or equal to maximumCount then exit repeat
        end repeat
        return exportItems(chosenItems, exportRoot, maximumCount)
    end run
    """#

    private static let applyScript = #"""
    on run argv
        set folderName to item 1 of argv
        set albumName to item 2 of argv
        set assetIDs to items 3 thru -1 of argv
        tell application "Photos"
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
            set selectedMediaItems to {}
            set requiredIDs to {}
            set outputText to "album" & tab & (id of targetAlbum as text) & linefeed
            set existingIDs to id of every media item of targetAlbum
            repeat with assetID in assetIDs
                set assetID to assetID as text
                set matchingItems to every media item whose id is assetID
                if (count of matchingItems) is 0 then
                    set outputText to outputText & "missing" & tab & assetID & linefeed
                else if assetID is in existingIDs then
                    set end of requiredIDs to assetID
                    set outputText to outputText & "existing" & tab & assetID & linefeed
                else
                    set end of requiredIDs to assetID
                    set end of selectedMediaItems to item 1 of matchingItems
                    set outputText to outputText & "added" & tab & assetID & linefeed
                end if
            end repeat
            if (count of selectedMediaItems) > 0 then add selectedMediaItems to targetAlbum
            set confirmedIDs to id of every media item of targetAlbum
            repeat with assetID in requiredIDs
                set assetID to assetID as text
                if assetID is not in confirmedIDs then error "Photos 未确认相册成员，保留未知回执"
            end repeat
            return outputText
        end tell
    end run
    """#
}

public struct PhotoLibraryApplyError: LocalizedError {
    public let confirmedCount: Int
    public let uncertainAlbumName: String
    public let underlyingMessage: String

    public var errorDescription: String? {
        "相册写入中断：之前的相册已确认加入 \(confirmedCount) 张；\(uncertainAlbumName) 的写入结果未知。"
        + "后续相册未处理，已完成的写入没有回滚。请先检查 Photos 并保留原计划，再决定是否重试。\(underlyingMessage)"
    }
}
