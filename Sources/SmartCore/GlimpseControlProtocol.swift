import Foundation

#if os(macOS)

public struct GlimpseControlTaskStatus: Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let state: String
    public let processed: Int
    public let total: Int
}

public struct GlimpseControlStatus: Codable, Equatable, Sendable {
    public let tasks: [GlimpseControlTaskStatus]

    init(tasks: [PhotoClassificationTask]) {
        self.tasks = tasks.map {
            GlimpseControlTaskStatus(
                id: $0.id,
                title: $0.title,
                state: $0.state.rawValue,
                processed: $0.results.count,
                total: $0.assetFingerprints.count
            )
        }
    }
}

public enum GlimpseControlAction: String, Codable, Equatable, Sendable {
    case createRecent
    case continueTask
    case reviewTask
}

public struct GlimpseControlCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let action: GlimpseControlAction
    public let taskID: UUID?
    public let recentDays: Int?
    public let modelIdentifier: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        action: GlimpseControlAction,
        taskID: UUID?,
        recentDays: Int?,
        modelIdentifier: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.taskID = taskID
        self.recentDays = recentDays
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
    }
}

public struct GlimpseControlInbox: Sendable {
    public let directory: URL

    public init(directory: URL = GlimpseControlFiles.commandDirectory) {
        self.directory = directory
    }

    public func submit(_ command: GlimpseControlCommand) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(command.id.uuidString).json")
        try JSONEncoder().encode(command).write(to: destination, options: .atomic)
    }

    public func consume() throws -> [GlimpseControlCommand] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var commands: [GlimpseControlCommand] = []
        for url in urls {
            let command = try JSONDecoder().decode(
                GlimpseControlCommand.self,
                from: Data(contentsOf: url)
            )
            commands.append(command)
            try FileManager.default.removeItem(at: url)
        }
        return commands
    }
}

public enum GlimpseControlFiles {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Glimpse", isDirectory: true)
    }

    public static var commandDirectory: URL {
        directory.appendingPathComponent("commands", isDirectory: true)
    }

    public static var statusURL: URL { directory.appendingPathComponent("status.json") }

    static func write(_ status: GlimpseControlStatus) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(status).write(to: statusURL, options: .atomic)
    }
}
#endif
