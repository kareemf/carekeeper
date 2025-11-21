@testable import CareKeeper
import XCTest

@MainActor
final class ShareAcceptanceRefresherTests: XCTestCase {
    func testRefreshStopsAfterNewCareeArrives() async throws {
        let sharedService = MockSharedCareeService()
        let cacheService = MockCacheRefreshingService()
        let center = NotificationCenter()

        _ = ShareAcceptanceRefresher(
            sharedRecordsService: sharedService,
            cacheService: cacheService,
            notificationCenter: center,
            retryDelays: [0.01, 0.02, 0.03]
        )

        sharedService.onFetch = {
            if sharedService.fetchCallCount == 2 {
                sharedService.sharedCarees = [Caree(name: "New Caree")]
            }
        }

        center.post(name: .cloudKitShareAccepted, object: nil)

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(sharedService.fetchCallCount, 2, "Should stop retries after detecting new caree")
        XCTAssertEqual(cacheService.refreshCount, 2, "Cache refresh should run alongside each fetch")
    }

    func testSubsequentAcceptanceCancelsPendingRefresh() async throws {
        let sharedService = MockSharedCareeService()
        let cacheService = MockCacheRefreshingService()
        let center = NotificationCenter()

        _ = ShareAcceptanceRefresher(
            sharedRecordsService: sharedService,
            cacheService: cacheService,
            notificationCenter: center,
            retryDelays: [0.2, 0.2, 0.2]
        )

        sharedService.onFetch = {
            if sharedService.fetchCallCount == 1 {
                sharedService.sharedCarees = [Caree(name: "Second Acceptance Caree")]
            }
        }

        center.post(name: .cloudKitShareAccepted, object: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        center.post(name: .cloudKitShareAccepted, object: nil)

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(sharedService.fetchCallCount, 1, "Earlier refresh should be cancelled when a new acceptance arrives")
        XCTAssertEqual(cacheService.refreshCount, 1, "Cache refresh should mirror the single active attempt")
    }
}

// MARK: - Test Doubles

@MainActor
private final class MockSharedCareeService: SharedCareeRefreshable {
    var sharedCarees: [Caree] = []
    var fetchCallCount = 0
    var onFetch: (() -> Void)?

    func fetchSharedCarees() async {
        fetchCallCount += 1
        onFetch?()
    }
}

@MainActor
private final class MockCacheRefreshingService: CacheRefreshing {
    var refreshCount = 0

    func invalidateAndRefresh() async throws {
        refreshCount += 1
    }
}
