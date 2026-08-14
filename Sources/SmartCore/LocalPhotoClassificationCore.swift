import Foundation

enum PhotoClassificationSchemeKind: String, Codable, Hashable, Sendable {
    case ordinary
    case screenshot
}

struct PhotoClassificationCategory: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var classificationDescription: String
    var isEnabled: Bool
}

struct PhotoClassificationScheme: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let kind: PhotoClassificationSchemeKind
    var version: Int
    var categories: [PhotoClassificationCategory]

    static let ordinaryDefault = PhotoClassificationScheme(
        id: UUID(uuidString: "A417D54F-A4D1-442C-A411-5892807E8201")!,
        name: "普通照片",
        kind: .ordinary,
        version: 1,
        categories: [
            .init(id: "people", name: "人物与自拍", classificationDescription: "人物照、合照或自拍，不识别具体身份", isEnabled: true),
            .init(id: "pets", name: "宠物", classificationDescription: "猫、狗及其他宠物是画面主体", isEnabled: true),
            .init(id: "food", name: "美食", classificationDescription: "菜品、饮料或餐桌是画面主体", isEnabled: true),
            .init(id: "travel", name: "旅行与地标", classificationDescription: "旅行记录、城市街景或明确地标", isEnabled: true),
            .init(id: "nature", name: "自然风景", classificationDescription: "山水、海滩、天空、植物等自然景观", isEnabled: true),
            .init(id: "work-study", name: "工作学习", classificationDescription: "白板、纸质资料、课堂或办公内容", isEnabled: true),
            .init(id: "products", name: "商品物品", classificationDescription: "商品、设备或其他物品是画面主体", isEnabled: true),
            .init(id: "other", name: "其他", classificationDescription: "不适合以上任何分类", isEnabled: true)
        ]
    )

    static let screenshotDefault = PhotoClassificationScheme(
        id: UUID(uuidString: "0B7E9F61-256E-4E4C-840E-65DF8C564C62")!,
        name: "截图",
        kind: .screenshot,
        version: 1,
        categories: [
            .init(id: "social", name: "聊天社交", classificationDescription: "聊天记录、社交动态或联系人内容", isEnabled: true),
            .init(id: "knowledge", name: "文章知识", classificationDescription: "文章、教程、书摘或知识资料", isEnabled: true),
            .init(id: "work-study", name: "工作学习", classificationDescription: "工作消息、文档、课程或学习资料", isEnabled: true),
            .init(id: "orders", name: "订单票据", classificationDescription: "订单、支付、账单、发票或票据", isEnabled: true),
            .init(id: "shopping", name: "购物商品", classificationDescription: "商品详情、比价或购物清单", isEnabled: true),
            .init(id: "maps", name: "地图行程", classificationDescription: "地图、导航、车票、航班或行程", isEnabled: true),
            .init(id: "entertainment", name: "娱乐梗图", classificationDescription: "影视、游戏、音乐、表情包或梗图", isEnabled: true),
            .init(id: "software", name: "软件系统", classificationDescription: "软件界面、设置、报错或系统信息", isEnabled: true),
            .init(id: "other", name: "其他", classificationDescription: "不适合以上任何分类", isEnabled: true)
        ]
    )
}

struct PhotoClassificationFingerprint: Codable, Hashable, Sendable {
    let assetIdentifier: String
    let modificationDate: Date?
    let modelIdentifier: String
    let analyzerVersion: Int
    let schemeVersion: Int
}

struct PhotoClassificationResult: Codable, Hashable, Identifiable, Sendable {
    let fingerprint: PhotoClassificationFingerprint
    let categoryIdentifier: String?
    let reason: String
    var reviewedCategoryIdentifier: String?

    var id: String { fingerprint.assetIdentifier }

    var effectiveCategoryIdentifier: String? {
        reviewedCategoryIdentifier ?? categoryIdentifier
    }
}

enum PhotoClassificationPlanner {
    static func assetsRequiringClassification(
        current: [PhotoClassificationFingerprint],
        cached: [PhotoClassificationResult]
    ) -> [PhotoClassificationFingerprint] {
        let cachedByIdentifier = Dictionary(
            uniqueKeysWithValues: cached.map { ($0.fingerprint.assetIdentifier, $0) }
        )
        return current.filter { fingerprint in
            cachedByIdentifier[fingerprint.assetIdentifier]?.fingerprint != fingerprint
        }
    }
}

enum PhotoAlbumTarget: Codable, Hashable, Sendable {
    case newAlbum(name: String)
    case existingAlbum(identifier: String, name: String)
    case skip
}

struct PhotoAlbumAddition: Codable, Hashable, Sendable {
    let assetIdentifier: String
    let categoryIdentifier: String
    let target: PhotoAlbumTarget
}

enum PhotoAlbumMutationPlanner {
    static func additions(
        results: [PhotoClassificationResult],
        approvedAssetIdentifiers: Set<String>,
        targetsByCategory: [String: PhotoAlbumTarget]
    ) -> [PhotoAlbumAddition] {
        results.compactMap { result in
            guard approvedAssetIdentifiers.contains(result.id),
                  let categoryIdentifier = result.effectiveCategoryIdentifier,
                  let target = targetsByCategory[categoryIdentifier],
                  target != .skip else {
                return nil
            }
            return PhotoAlbumAddition(
                assetIdentifier: result.id,
                categoryIdentifier: categoryIdentifier,
                target: target
            )
        }
    }
}

struct PhotoClassificationResponse: Codable, Equatable, Sendable {
    let categoryIdentifier: String?
    let reason: String

    private enum CodingKeys: String, CodingKey {
        case categoryIdentifier = "category"
        case reason
    }
}

enum PhotoClassificationResponseError: LocalizedError, Equatable {
    case unknownCategory(String)
    case emptyReason

    var errorDescription: String? {
        switch self {
        case .unknownCategory(let identifier):
            return "模型返回了未启用的分类：\(identifier)"
        case .emptyReason:
            return "模型没有提供分类理由"
        }
    }
}

struct PhotoClassificationResponseDecoder: Sendable {
    let allowedCategoryIdentifiers: Set<String>

    init(allowedCategoryIdentifiers: Set<String>) {
        self.allowedCategoryIdentifiers = allowedCategoryIdentifiers
    }

    func decode(_ content: String) throws -> PhotoClassificationResponse {
        let response = try JSONDecoder().decode(
            PhotoClassificationResponse.self,
            from: Data(content.utf8)
        )
        let reason = response.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            throw PhotoClassificationResponseError.emptyReason
        }
        guard let categoryIdentifier = response.categoryIdentifier else {
            return PhotoClassificationResponse(categoryIdentifier: nil, reason: reason)
        }
        guard allowedCategoryIdentifiers.contains(categoryIdentifier) else {
            throw PhotoClassificationResponseError.unknownCategory(categoryIdentifier)
        }
        return PhotoClassificationResponse(categoryIdentifier: categoryIdentifier, reason: reason)
    }
}
