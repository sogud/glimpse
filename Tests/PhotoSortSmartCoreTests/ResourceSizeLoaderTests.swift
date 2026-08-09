import XCTest
@testable import PhotoSortSmartCore

final class ResourceSizeLoaderTests: XCTestCase {
    func testReturnsTheTotalBytesReceivedFromTheResource() {
        let source = ResourceDataSourceStub(chunks: [Data(count: 3), Data(count: 5)])
        let loader = ResourceSizeLoader(source: source)
        var result: Result<Int64, Error>?

        loader.load { result = $0 }

        XCTAssertEqual(try result?.get(), 8)
    }

    func testCancelForwardsTheActiveSystemRequestIdentifier() {
        let source = ResourceDataSourceStub(chunks: [], completesImmediately: false)
        let loader = ResourceSizeLoader(source: source)

        loader.load { _ in XCTFail("取消后不应完成大小读取") }
        loader.cancel()

        XCTAssertEqual(source.cancelledRequestIdentifiers, [42])
    }
}

private final class ResourceDataSourceStub: ResourceDataSource {
    let chunks: [Data]
    let completesImmediately: Bool
    private(set) var cancelledRequestIdentifiers: [Int32] = []

    init(chunks: [Data], completesImmediately: Bool = true) {
        self.chunks = chunks
        self.completesImmediately = completesImmediately
    }

    func requestData(
        received: @escaping (Data) -> Void,
        completion: @escaping (Error?) -> Void
    ) -> Int32 {
        chunks.forEach(received)
        if completesImmediately {
            completion(nil)
        }
        return 42
    }

    func cancel(requestID: Int32) {
        cancelledRequestIdentifiers.append(requestID)
    }
}
