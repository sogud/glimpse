import Foundation
import SwiftData
import Darwin

@Model
final class PhotoClassificationTaskEntity {
    @Attribute(.unique) var identifier: String
    var updatedAt: Date
    var payload: Data

    init(identifier: String, updatedAt: Date, payload: Data) {
        self.identifier = identifier
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

@MainActor
final class PhotoClassificationTaskStore {
    private let context: ModelContext
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    static func nativeContainer(directory: URL) throws -> ModelContainer {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let attributes = try fileManager.attributesOfItem(atPath: directory.path)
        guard values.isDirectory == true, values.isSymbolicLink != true,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else { throw CocoaError(.fileReadNoPermission) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Tasks.store"))
        return try ModelContainer(for: PhotoClassificationTaskEntity.self, configurations: configuration)
    }

    init(container: ModelContainer) {
        context = ModelContext(container)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ task: PhotoClassificationTask) throws {
        let identifier = task.id.uuidString
        let payload = try encoder.encode(task)
        if let entity = try entities().first(where: { $0.identifier == identifier }) {
            entity.updatedAt = task.updatedAt
            entity.payload = payload
        } else {
            context.insert(
                PhotoClassificationTaskEntity(
                    identifier: identifier,
                    updatedAt: task.updatedAt,
                    payload: payload
                )
            )
        }
        try context.save()
    }

    func task(id: UUID) throws -> PhotoClassificationTask? {
        guard let entity = try entities().first(where: { $0.identifier == id.uuidString }) else {
            return nil
        }
        return try decoder.decode(PhotoClassificationTask.self, from: entity.payload)
    }

    func tasks() throws -> [PhotoClassificationTask] {
        try entities()
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { try decoder.decode(PhotoClassificationTask.self, from: $0.payload) }
    }

    func delete(id: UUID) throws {
        for entity in try entities() where entity.identifier == id.uuidString {
            context.delete(entity)
        }
        try context.save()
    }

    private func entities() throws -> [PhotoClassificationTaskEntity] {
        try context.fetch(FetchDescriptor<PhotoClassificationTaskEntity>())
    }
}
