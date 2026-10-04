import Foundation

enum PhotoClassificationSchemeKind: String, Codable, Hashable, Sendable {
    case ordinary
    case screenshot
}

struct PhotoClassificationCategoryID: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CodingKeyRepresentable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(schemeKind: PhotoClassificationSchemeKind, localIdentifier: String) {
        rawValue = "\(schemeKind.rawValue):\(localIdentifier)"
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var codingKey: any CodingKey {
        CategoryCodingKey(stringValue: rawValue)!
    }

    init?<Key>(codingKey: Key) where Key: CodingKey {
        rawValue = codingKey.stringValue
    }

    private struct CategoryCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

struct PhotoClassificationCategory: Codable, Hashable, Identifiable, Sendable {
    let id: PhotoClassificationCategoryID
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
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "people"), name: "人物与自拍", classificationDescription: "人物照、合照或自拍，不识别具体身份", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "pets"), name: "宠物", classificationDescription: "猫、狗及其他宠物是画面主体", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "food"), name: "美食", classificationDescription: "菜品、饮料或餐桌是画面主体", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "travel"), name: "旅行与地标", classificationDescription: "旅行记录、城市街景或明确地标", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "nature"), name: "自然风景", classificationDescription: "山水、海滩、天空、植物等自然景观", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "work-study"), name: "工作学习", classificationDescription: "白板、纸质资料、课堂或办公内容", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "products"), name: "商品物品", classificationDescription: "商品、设备或其他物品是画面主体", isEnabled: true),
            .init(id: .init(schemeKind: .ordinary, localIdentifier: "other"), name: "其他", classificationDescription: "不适合以上任何分类", isEnabled: true)
        ]
    )

    static let screenshotDefault = PhotoClassificationScheme(
        id: UUID(uuidString: "0B7E9F61-256E-4E4C-840E-65DF8C564C62")!,
        name: "截图",
        kind: .screenshot,
        version: 1,
        categories: [
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "social"), name: "聊天社交", classificationDescription: "聊天记录、社交动态或联系人内容", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "knowledge"), name: "文章知识", classificationDescription: "文章、教程、书摘或知识资料", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "work-study"), name: "工作学习", classificationDescription: "工作消息、文档、课程或学习资料", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "orders"), name: "订单票据", classificationDescription: "订单、支付、账单、发票或票据", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "shopping"), name: "购物商品", classificationDescription: "商品详情、比价或购物清单", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "maps"), name: "地图行程", classificationDescription: "地图、导航、车票、航班或行程", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "entertainment"), name: "娱乐梗图", classificationDescription: "影视、游戏、音乐、表情包或梗图", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "software"), name: "软件系统", classificationDescription: "软件界面、设置、报错或系统信息", isEnabled: true),
            .init(id: .init(schemeKind: .screenshot, localIdentifier: "other"), name: "其他", classificationDescription: "不适合以上任何分类", isEnabled: true)
        ]
    )

    mutating func updateCategory(_ category: PhotoClassificationCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }),
              categories[index] != category else { return }
        categories[index] = category
        version += 1
    }

    mutating func appendCategory(_ category: PhotoClassificationCategory) {
        guard !categories.contains(where: { $0.id == category.id }) else { return }
        categories.append(category)
        version += 1
    }

    mutating func removeCategory(id: PhotoClassificationCategoryID) {
        guard categories.contains(where: { $0.id == id }) else { return }
        categories.removeAll { $0.id == id }
        version += 1
    }

    @discardableResult
    mutating func namespaceLegacyCategoryIdentifiers() -> Bool {
        var changed = false
        categories = categories.map { category in
            guard !category.id.rawValue.contains(":") else { return category }
            changed = true
            return PhotoClassificationCategory(
                id: PhotoClassificationCategoryID(
                    schemeKind: kind,
                    localIdentifier: category.id.rawValue
                ),
                name: category.name,
                classificationDescription: category.classificationDescription,
                isEnabled: category.isEnabled
            )
        }
        if changed {
            version += 1
        }
        return changed
    }
}

struct PhotoClassificationFingerprint: Codable, Hashable, Sendable {
    let assetIdentifier: String
    let modificationDate: Date?
    let modelIdentifier: String
    let analyzerVersion: Int
    let schemeIdentifier: UUID
    let schemeVersion: Int
}

struct PhotoClassificationResult: Codable, Hashable, Identifiable, Sendable {
    let fingerprint: PhotoClassificationFingerprint
    let categoryIdentifier: PhotoClassificationCategoryID?
    let reason: String
    var reviewedCategoryIdentifier: PhotoClassificationCategoryID?

    var id: String { fingerprint.assetIdentifier }

    var effectiveCategoryIdentifier: PhotoClassificationCategoryID? {
        reviewedCategoryIdentifier ?? categoryIdentifier
    }
}

enum PhotoClassificationPlanner {
    static func albumName(schemeName: String, categoryName: String) -> String {
        "\(schemeName)·\(categoryName)"
    }

    static func defaultTargets(schemes: [PhotoClassificationScheme]) -> [PhotoClassificationCategoryID: PhotoAlbumTarget] {
        var targets: [PhotoClassificationCategoryID: PhotoAlbumTarget] = [:]
        for scheme in schemes {
            for category in scheme.categories where category.isEnabled {
                targets[category.id] = .newAlbum(name: albumName(schemeName: scheme.name, categoryName: category.name))
            }
        }
        return targets
    }

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

    static func reusableResults(
        current: [PhotoClassificationFingerprint],
        cached: [PhotoClassificationResult]
    ) -> [PhotoClassificationResult] {
        let cachedByFingerprint = cached.reduce(into: [PhotoClassificationFingerprint: PhotoClassificationResult]()) {
            result, cachedResult in
            result[cachedResult.fingerprint] = result[cachedResult.fingerprint] ?? cachedResult
        }
        return current.compactMap { fingerprint in
            guard let cachedResult = cachedByFingerprint[fingerprint] else { return nil }
            return PhotoClassificationResult(
                fingerprint: fingerprint,
                categoryIdentifier: cachedResult.categoryIdentifier,
                reason: cachedResult.reason,
                reviewedCategoryIdentifier: nil
            )
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
    let categoryIdentifier: PhotoClassificationCategoryID
    let target: PhotoAlbumTarget
}

enum PhotoAlbumMutationPlanner {
    static func additions(
        results: [PhotoClassificationResult],
        approvedAssetIdentifiers: Set<String>,
        targetsByCategory: [PhotoClassificationCategoryID: PhotoAlbumTarget]
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
    let categoryIdentifier: PhotoClassificationCategoryID?
    let reason: String

    private enum CodingKeys: String, CodingKey {
        case categoryIdentifier = "category"
        case reason
    }

    init(categoryIdentifier: PhotoClassificationCategoryID?, reason: String) {
        self.categoryIdentifier = categoryIdentifier
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryIdentifier = try container.decode(PhotoClassificationCategoryID?.self, forKey: .categoryIdentifier)
        reason = try container.decode(String.self, forKey: .reason)
    }
}

enum PhotoClassificationResponseError: LocalizedError, Equatable {
    case unknownCategory(PhotoClassificationCategoryID)
    case emptyReason

    var errorDescription: String? {
        switch self {
        case .unknownCategory(let identifier):
            return "模型返回了未启用的分类：\(identifier.rawValue)"
        case .emptyReason:
            return "模型没有提供分类理由"
        }
    }
}

struct PhotoClassificationResponseDecoder: Sendable {
    let allowedCategoryIdentifiers: Set<PhotoClassificationCategoryID>

    init(allowedCategoryIdentifiers: Set<PhotoClassificationCategoryID>) {
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
