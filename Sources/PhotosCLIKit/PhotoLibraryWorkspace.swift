import Darwin
import Foundation

public struct PhotoLibraryWorkspace: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var current: Self {
        if let path = ProcessInfo.processInfo.environment["GLIMPSE_HOME"], !path.isEmpty {
            return Self(directory: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath))
        }
        return Self(directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Glimpse/CLI", isDirectory: true))
    }

    public func acquireLock() throws -> PhotoLibraryWorkspaceLock {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try validateDirectory()
        return try PhotoLibraryWorkspaceLock(urls: [
            directory.appendingPathComponent("write.lock"),
            FileManager.default.temporaryDirectory.appendingPathComponent("glimpse-photos-write.lock")
        ])
    }

    func validateDirectory() throws {
        var attributes = stat()
        guard lstat(directory.path, &attributes) == 0 else {
            if errno == ENOENT { return }
            throw PhotoLibraryCLIUsageError("无法检查运行目录")
        }
        guard attributes.st_mode & S_IFMT == S_IFDIR,
              attributes.st_uid == geteuid(), attributes.st_mode & 0o077 == 0 else {
            throw PhotoLibraryCLIUsageError("运行目录必须是当前用户拥有的私人目录（0700），不能是软链接或共享目录")
        }
    }

    public func loadState() throws -> PhotoLibraryBatchState {
        try validateDirectory()
        let url = directory.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return PhotoLibraryBatchState() }
        return try JSONDecoder().decode(PhotoLibraryBatchState.self, from: Data(contentsOf: url))
    }

    public func saveState(_ state: PhotoLibraryBatchState) throws {
        try validateDirectory()
        let url = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public final class PhotoLibraryWorkspaceLock {
    private var descriptors: [Int32] = []

    fileprivate init(urls: [URL]) throws {
        do {
            for url in urls {
                let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw PhotoLibraryCLIUsageError("无法打开工作区锁文件") }
                guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                    close(descriptor)
                    throw PhotoLibraryCLIUsageError("另一个 Glimpse 写进程正在运行，请等待它完成")
                }
                descriptors.append(descriptor)
            }
        } catch {
            for descriptor in descriptors { close(descriptor) }
            throw error
        }
    }

    deinit {
        for descriptor in descriptors {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
    }
}
