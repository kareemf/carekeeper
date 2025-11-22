@testable import CareKeeper
import XCTest

@MainActor
final class ShareAcceptanceRefresherTests: XCTestCase {
    func testRefreshStopsAfterNewCareeArrives() async throws {
        let sharedService = MockSharedCareeService()
        let cacheService = MockCacheRefreshingService()
        let center = NotificationCenter()
        let fetchExpectation = expectation(description: "Fetch called twice")
        let cacheExpectation = expectation(description: "Cache refreshed twice")

        let refresher = ShareAcceptanceRefresher(
            sharedRecordsService: sharedService,
            cacheService: cacheService,
            notificationCenter: center,
            retryDelays: [0.01, 0.02, 0.03]
        )

        sharedService.onFetch = {
            if sharedService.fetchCallCount == 2 {
                sharedService.setSharedCarees([CareKeeper.Caree(name: "New Caree")])
                fetchExpectation.fulfill()
            }
        }
        cacheService.onRefresh = {
            if cacheService.refreshCount == 2 {
                cacheExpectation.fulfill()
            }
        }

        refresher.handleShareAcceptance()

        await fulfillment(of: [fetchExpectation, cacheExpectation], timeout: 2.0)

        XCTAssertEqual(sharedService.fetchCallCount, 2, "Should stop retries after detecting new caree")
        XCTAssertEqual(cacheService.refreshCount, 2, "Cache refresh should run alongside each fetch")
    }

    func testSubsequentAcceptanceCancelsPendingRefresh() async throws {
        let sharedService = MockSharedCareeService()
        let cacheService = MockCacheRefreshingService()
        let center = NotificationCenter()
        let fetchExpectation = expectation(description: "Fetch called once after restart")
        let cacheExpectation = expectation(description: "Cache refreshed once after restart")

        let refresher = ShareAcceptanceRefresher(
            sharedRecordsService: sharedService,
            cacheService: cacheService,
            notificationCenter: center,
            retryDelays: [0.2, 0.2, 0.2]
        )

        sharedService.onFetch = {
            if sharedService.fetchCallCount == 1 {
                sharedService.setSharedCarees([CareKeeper.Caree(name: "Second Acceptance Caree")])
                fetchExpectation.fulfill()
            }
        }
        cacheService.onRefresh = {
            if cacheService.refreshCount == 1 {
                cacheExpectation.fulfill()
            }
        }

        refresher.handleShareAcceptance()
        try await Task.sleep(nanoseconds: 50_000_000)
        refresher.handleShareAcceptance()

        await fulfillment(of: [fetchExpectation, cacheExpectation], timeout: 2.0)

        XCTAssertEqual(sharedService.fetchCallCount, 1, "Earlier refresh should be cancelled when a new acceptance arrives")
        XCTAssertEqual(cacheService.refreshCount, 1, "Cache refresh should mirror the single active attempt")
    }
}

// MARK: - Test Doubles

@MainActor
private final class MockSharedCareeService: SharedCareeRefreshable {
    private var stored: [CareKeeper.Caree] = []
    @MainActor var sharedCarees: [CareKeeper.Caree] { stored }
    var fetchCallCount = 0
    var onFetch: (() -> Void)?

    func fetchSharedCarees() async {
        fetchCallCount += 1
        onFetch?()
    }

    func setSharedCarees(_ carees: [CareKeeper.Caree]) {
        stored = carees
    }
}

@MainActor
private final class MockCacheRefreshingService: CacheRefreshing {
    var refreshCount = 0
    var onRefresh: (() -> Void)?

    func invalidateAndRefresh() async throws {
        refreshCount += 1
        onRefresh?()
    }
}
