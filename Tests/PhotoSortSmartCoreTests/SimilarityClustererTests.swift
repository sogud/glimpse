import XCTest
@testable import PhotoSortSmartCore

final class SimilarityClustererTests: XCTestCase {
    func testBuildsAClusterAndRecommendsTheHighestQualityKeeper() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let candidates = [
            SimilarityCandidate(
                id: "a",
                capturedAt: capturedAt,
                pixelWidth: 3000,
                pixelHeight: 2000,
                featureVector: [0, 0],
                sharpness: 0.55,
                faceQuality: 0.4,
                estimatedBytes: 1_000
            ),
            SimilarityCandidate(
                id: "b",
                capturedAt: capturedAt.addingTimeInterval(2),
                pixelWidth: 3200,
                pixelHeight: 2100,
                featureVector: [0.05, 0.02],
                sharpness: 0.9,
                faceQuality: 0.8,
                estimatedBytes: 1_200
            ),
            SimilarityCandidate(
                id: "c",
                capturedAt: capturedAt.addingTimeInterval(4),
                pixelWidth: 3000,
                pixelHeight: 2000,
                featureVector: [0.06, 0.03],
                sharpness: 0.6,
                faceQuality: 0.5,
                estimatedBytes: 900
            ),
            SimilarityCandidate(
                id: "unrelated",
                capturedAt: capturedAt.addingTimeInterval(3),
                pixelWidth: 3000,
                pixelHeight: 2000,
                featureVector: [5, 5],
                sharpness: 1,
                faceQuality: 1,
                estimatedBytes: 1_500
            )
        ]

        let clusters = SimilarityClusterer().clusters(from: candidates)

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(Set(clusters[0].memberIdentifiers), ["a", "b", "c"])
        XCTAssertEqual(clusters[0].recommendedKeeperIdentifier, "b")
        XCTAssertEqual(clusters[0].reviewIdentifiers.sorted(), ["a", "c"])
    }
}
