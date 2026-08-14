import SwiftData
import XCTest
@testable import PhotoSortSmartCore

final class LocalPhotoClassificationTests: XCTestCase {
    func testDecodesAClassificationOnlyWhenTheCategoryIsAllowed() throws {
        let decoder = PhotoClassificationResponseDecoder(
            allowedCategoryIdentifiers: ["pets", "food"]
        )

        let result = try decoder.decode(
            """
            {"category":"pets","reason":"画面主体是一只猫"}
            """
        )

        XCTAssertEqual(result.categoryIdentifier, "pets")
        XCTAssertEqual(result.reason, "画面主体是一只猫")
        XCTAssertThrowsError(
            try decoder.decode(
                """
                {"category":"travel","reason":"未知分类"}
                """
            )
        )
    }

    func testDefaultSchemesKeepOrdinaryPhotosAndScreenshotsSeparate() {
        let ordinary = PhotoClassificationScheme.ordinaryDefault
        let screenshots = PhotoClassificationScheme.screenshotDefault

        XCTAssertEqual(ordinary.kind, .ordinary)
        XCTAssertEqual(
            ordinary.categories.map(\.name),
            ["人物与自拍", "宠物", "美食", "旅行与地标", "自然风景", "工作学习", "商品物品", "其他"]
        )
        XCTAssertEqual(screenshots.kind, .screenshot)
        XCTAssertEqual(
            screenshots.categories.map(\.name),
            ["聊天社交", "文章知识", "工作学习", "订单票据", "购物商品", "地图行程", "娱乐梗图", "软件系统", "其他"]
        )
    }

    func testContinuationSchedulesOnlyUnfinishedOrStaleAssets() {
        let originalDate = Date(timeIntervalSince1970: 100)
        let current = [
            PhotoClassificationFingerprint(
                assetIdentifier: "fresh",
                modificationDate: originalDate,
                modelIdentifier: "vision-model",
                analyzerVersion: 1,
                schemeVersion: 1
            ),
            PhotoClassificationFingerprint(
                assetIdentifier: "changed",
                modificationDate: originalDate.addingTimeInterval(10),
                modelIdentifier: "vision-model",
                analyzerVersion: 1,
                schemeVersion: 1
            ),
            PhotoClassificationFingerprint(
                assetIdentifier: "unfinished",
                modificationDate: nil,
                modelIdentifier: "vision-model",
                analyzerVersion: 1,
                schemeVersion: 1
            )
        ]
        let cached = [
            PhotoClassificationResult(
                fingerprint: current[0],
                categoryIdentifier: "pets",
                reason: "猫",
                reviewedCategoryIdentifier: nil
            ),
            PhotoClassificationResult(
                fingerprint: PhotoClassificationFingerprint(
                    assetIdentifier: "changed",
                    modificationDate: originalDate,
                    modelIdentifier: "vision-model",
                    analyzerVersion: 1,
                    schemeVersion: 1
                ),
                categoryIdentifier: "pets",
                reason: "猫",
                reviewedCategoryIdentifier: nil
            )
        ]

        let pending = PhotoClassificationPlanner.assetsRequiringClassification(
            current: current,
            cached: cached
        )

        XCTAssertEqual(pending.map(\.assetIdentifier), ["changed", "unfinished"])
    }

    func testApplyPlanUsesReviewedCategoryAndSkipsDisabledTargets() {
        let fingerprint = PhotoClassificationFingerprint(
            assetIdentifier: "photo-1",
            modificationDate: nil,
            modelIdentifier: "vision-model",
            analyzerVersion: 1,
            schemeVersion: 1
        )
        let results = [
            PhotoClassificationResult(
                fingerprint: fingerprint,
                categoryIdentifier: "pets",
                reason: "猫",
                reviewedCategoryIdentifier: "food"
            ),
            PhotoClassificationResult(
                fingerprint: PhotoClassificationFingerprint(
                    assetIdentifier: "photo-2",
                    modificationDate: nil,
                    modelIdentifier: "vision-model",
                    analyzerVersion: 1,
                    schemeVersion: 1
                ),
                categoryIdentifier: "pets",
                reason: "狗",
                reviewedCategoryIdentifier: nil
            )
        ]

        let additions = PhotoAlbumMutationPlanner.additions(
            results: results,
            approvedAssetIdentifiers: ["photo-1", "photo-2"],
            targetsByCategory: [
                "food": .newAlbum(name: "美食"),
                "pets": .skip
            ]
        )

        XCTAssertEqual(
            additions,
            [PhotoAlbumAddition(assetIdentifier: "photo-1", categoryIdentifier: "food", target: .newAlbum(name: "美食"))]
        )
    }

    @MainActor
    func testTaskStoreRoundTripsProgressWithoutMediaPayloads() throws {
        let container = try ModelContainer(
            for: PhotoClassificationTaskEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = PhotoClassificationTaskStore(container: container)
        let task = PhotoClassificationTask(
            id: UUID(uuidString: "890D76EE-2479-453A-83DF-2A0D1CF81C19")!,
            title: "最近 7 天",
            source: .recentDays(7),
            state: .paused,
            modelIdentifier: "vision-model",
            ordinaryScheme: .ordinaryDefault,
            screenshotScheme: .screenshotDefault,
            assetFingerprints: [],
            results: [],
            targetsByCategory: [:],
            approvedAssetIdentifiers: [],
            mutations: [],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try store.save(task)

        XCTAssertEqual(try store.task(id: task.id), task)
        XCTAssertEqual(try store.tasks(), [task])
    }

    func testControlInboxConsumesEachCommandOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = GlimpseControlInbox(directory: directory)
        let command = GlimpseControlCommand(
            id: UUID(uuidString: "4B756619-C0E5-470F-A32A-64AF0B6170E1")!,
            action: .continueTask,
            taskID: UUID(uuidString: "AF81BF8B-49D2-49F2-8EAF-66D2374A5BA4"),
            recentDays: nil,
            modelIdentifier: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        try inbox.submit(command)

        XCTAssertEqual(try inbox.consume(), [command])
        XCTAssertEqual(try inbox.consume(), [])
    }
}
