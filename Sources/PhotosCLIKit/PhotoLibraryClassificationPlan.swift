import Darwin
import Foundation

public enum PhotoClassificationSchemeKind: String, Codable, Equatable, Sendable {
    case ordinary
    case screenshot
}

public struct PhotoClassificationCategory: Codable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let classificationDescription: String

    public init(identifier: String, name: String, classificationDescription: String) {
        self.identifier = identifier
        self.name = name
        self.classificationDescription = classificationDescription
    }
}

public struct PhotoClassificationScheme: Codable, Equatable, Sendable {
    public let kind: PhotoClassificationSchemeKind
    public let categories: [PhotoClassificationCategory]

    public init(kind: PhotoClassificationSchemeKind, categories: [PhotoClassificationCategory]) {
        self.kind = kind
        self.categories = categories
    }
}

public enum PhotoClassificationCatalog {
    public static let deletionCandidateIdentifiers: Set<String> = [
        "ordinary:delete-candidate",
        "screenshot:delete-candidate"
    ]

    public static let ordinary = PhotoClassificationScheme(
        kind: .ordinary,
        categories: [
            .init(identifier: "ordinary:people", name: "人物与自拍", classificationDescription: "人物照、合照或自拍，不识别具体身份"),
            .init(identifier: "ordinary:pets", name: "宠物", classificationDescription: "猫、狗及其他宠物是画面主体"),
            .init(identifier: "ordinary:food", name: "美食", classificationDescription: "菜品、饮料或餐桌是画面主体"),
            .init(identifier: "ordinary:travel", name: "旅行与地标", classificationDescription: "旅行记录、城市街景或明确地标"),
            .init(identifier: "ordinary:nature", name: "自然风景", classificationDescription: "山水、海滩、天空、植物等自然景观"),
            .init(identifier: "ordinary:work-study", name: "工作学习", classificationDescription: "白板、纸质资料、课堂或办公内容"),
            .init(identifier: "ordinary:products", name: "商品物品", classificationDescription: "商品、设备或其他物品是画面主体"),
            .init(identifier: "ordinary:delete-candidate", name: "待删除", classificationDescription: "仅限明显误拍、严重失焦、严重曝光、镜头遮挡或几乎无有效内容的照片；人物回忆、票据证据和唯一记录不得选择"),
            .init(identifier: "ordinary:other", name: "其他", classificationDescription: "不适合以上任何分类")
        ]
    )

    public static let screenshot = PhotoClassificationScheme(
        kind: .screenshot,
        categories: [
            .init(identifier: "screenshot:social", name: "聊天社交", classificationDescription: "聊天记录、社交动态或联系人内容"),
            .init(identifier: "screenshot:knowledge", name: "文章知识", classificationDescription: "文章、教程、书摘或知识资料"),
            .init(identifier: "screenshot:work-study", name: "工作学习", classificationDescription: "工作消息、文档、课程或学习资料"),
            .init(identifier: "screenshot:orders", name: "订单票据", classificationDescription: "订单、支付、账单、发票或票据"),
            .init(identifier: "screenshot:shopping", name: "购物商品", classificationDescription: "商品详情、比价或购物清单"),
            .init(identifier: "screenshot:maps", name: "地图行程", classificationDescription: "地图、导航、车票、航班或行程"),
            .init(identifier: "screenshot:entertainment", name: "娱乐梗图", classificationDescription: "影视、游戏、音乐、表情包或梗图"),
            .init(identifier: "screenshot:software", name: "软件系统", classificationDescription: "软件界面、设置、报错或系统信息"),
            .init(identifier: "screenshot:delete-candidate", name: "待删除", classificationDescription: "仅限空白、误触、无法阅读或明显没有信息价值的临时截图；不能确定是否仍有用时不得选择"),
            .init(identifier: "screenshot:other", name: "其他", classificationDescription: "不适合以上任何分类")
        ]
    )

    public static func scheme(for kind: PhotoClassificationSchemeKind) -> PhotoClassificationScheme {
        kind == .screenshot ? screenshot : ordinary
    }

    public static func schemeKind(forCategoryIdentifier identifier: String?) -> PhotoClassificationSchemeKind? {
        guard let identifier else { return nil }
        if ordinary.categories.contains(where: { $0.identifier == identifier }) { return .ordinary }
        if screenshot.categories.contains(where: { $0.identifier == identifier }) { return .screenshot }
        return nil
    }

}

public struct SelectedPhoto: Equatable, Sendable {
    public let identifier: String
    public let filename: String
    public let width: Int
    public let height: Int
    public let exportedURL: URL

    public init(identifier: String, filename: String, width: Int, height: Int, exportedURL: URL) {
        self.identifier = identifier
        self.filename = filename
        self.width = width
        self.height = height
        self.exportedURL = exportedURL
    }
}

public enum PhotoLibrarySelection {
    public static func schemeKind(filename: String, width: Int, height: Int) -> PhotoClassificationSchemeKind {
        let normalized = filename.lowercased()
        let screenshotMarkers = ["screenshot", "screen shot", "屏幕快照", "截屏", "截图"]
        return screenshotMarkers.contains(where: normalized.contains) ? .screenshot : .ordinary
    }
}

public struct PhotoLibraryClassificationItem: Codable, Equatable, Sendable {
    public let assetIdentifier: String
    public let filename: String
    public let schemeKind: PhotoClassificationSchemeKind
    public let categoryIdentifier: String?
    public let categoryName: String?
    public let reason: String
    public let analysisSucceeded: Bool

    public init(
        photo: SelectedPhoto,
        schemeKind: PhotoClassificationSchemeKind? = nil,
        categoryIdentifier: String?,
        categoryName: String?,
        reason: String,
        analysisSucceeded: Bool = true
    ) {
        assetIdentifier = photo.identifier
        filename = photo.filename
        if let schemeKind {
            self.schemeKind = schemeKind
        } else if let catalogKind = PhotoClassificationCatalog.schemeKind(
            forCategoryIdentifier: categoryIdentifier
        ) {
            self.schemeKind = catalogKind
        } else {
            self.schemeKind = PhotoLibrarySelection.schemeKind(
                filename: photo.filename,
                width: photo.width,
                height: photo.height
            )
        }
        self.categoryIdentifier = categoryIdentifier
        self.categoryName = categoryName
        self.reason = reason
        self.analysisSucceeded = analysisSucceeded
    }
}

public struct PhotoLibraryAlbumAddition: Codable, Equatable, Sendable {
    public let folderName: String
    public let albumName: String
    public let assetIdentifiers: [String]

    public init(folderName: String, albumName: String, assetIdentifiers: [String]) {
        self.folderName = folderName
        self.albumName = albumName
        self.assetIdentifiers = assetIdentifiers
    }
}

public struct PhotoLibraryClassificationPlan: Codable, Equatable, Sendable {
    public let id: UUID
    public let modelIdentifier: String
    public let createdAt: Date
    public let items: [PhotoLibraryClassificationItem]

    public init(
        id: UUID = UUID(),
        modelIdentifier: String,
        createdAt: Date = Date(),
        items: [PhotoLibraryClassificationItem]
    ) {
        self.id = id
        self.modelIdentifier = modelIdentifier
        self.createdAt = createdAt
        self.items = items
    }

    public func validatedAlbumAdditions() throws -> [PhotoLibraryAlbumAddition] {
        guard items.count <= PhotosAutomation.maximumExportCount else {
            throw PhotoLibraryPlanError.invalidItem("单个计划最多 10 项")
        }
        var seenIdentifiers: Set<String> = []
        var grouped: [String: [String]] = [:]
        for item in items {
            guard !item.assetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.assetIdentifier.utf8.count <= 512,
                  seenIdentifiers.insert(item.assetIdentifier).inserted else {
                throw PhotoLibraryPlanError.invalidItem("照片 ID 为空或重复")
            }
            guard let categoryIdentifier = item.categoryIdentifier else {
                guard item.categoryName == nil else {
                    throw PhotoLibraryPlanError.invalidItem("分类名称缺少对应 ID")
                }
                continue
            }
            let scheme = PhotoClassificationCatalog.scheme(for: item.schemeKind)
            guard item.analysisSucceeded,
                  let category = scheme.categories.first(where: { $0.identifier == categoryIdentifier }),
                  item.categoryName == category.name else {
                throw PhotoLibraryPlanError.invalidItem("分类 ID、名称、方案或分析状态不一致")
            }
            let schemeName = item.schemeKind == .screenshot ? "截图" : "普通照片"
            let isDeletionCandidate = PhotoClassificationCatalog.deletionCandidateIdentifiers.contains(categoryIdentifier)
            let albumName = isDeletionCandidate ? "待删除" : "\(schemeName)·\(category.name)"
            grouped[albumName, default: []].append(item.assetIdentifier)
        }
        return grouped.keys.sorted().map { albumName in
            PhotoLibraryAlbumAddition(
                folderName: "Glimpse",
                albumName: albumName,
                assetIdentifiers: grouped[albumName, default: []]
            )
        }
    }
}

public enum PhotoLibraryPlanError: LocalizedError {
    case invalidItem(String)
    case outputExists

    public var errorDescription: String? {
        switch self {
        case .invalidItem(let message): return "分类计划无效：\(message)，没有写入照片图库"
        case .outputExists: return "分类计划文件已存在，请选择新的 --output 路径"
        }
    }
}

public enum PhotoLibraryPlanStore {
    public static func prepareDestination(_ url: URL) throws {
        try checkDestination(url)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appendingPathComponent(".glimpse-write-check-\(UUID().uuidString)")
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }

    public static func checkDestination(_ url: URL) throws {
        // attributesOfItem 也能识别悬空软链接，不能把已有目录项当作新文件。
        if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
            throw PhotoLibraryPlanError.outputExists
        }
    }

    public static func save(_ plan: PhotoLibraryClassificationPlan, to url: URL) throws {
        _ = try plan.validatedAlbumAdditions()
        try checkDestination(url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // 排他创建：即使预检查后有另一进程创建同名文件，也不能覆盖它。
        let data = try encoder.encode(plan)
        let descriptor = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        do {
            try handle.write(contentsOf: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
