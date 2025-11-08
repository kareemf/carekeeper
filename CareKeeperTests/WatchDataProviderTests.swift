import XCTest
@testable import CareKeeperV2

@MainActor
final class WatchDataProviderTests: XCTestCase {

    func testLoadActivityTypesRefreshesAfterInitialFetch() async {
        let caree = CareeSnapshot(
            id: UUID(),
            name: "Taylor",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let selectiveService = MockSelectiveCloudKitService()
        selectiveService.activityTypesByCaree[caree.id] = [
            ActivityTypeSnapshot(
                name: "Meals",
                icon: "🍽",
                careeID: caree.id
            )
        ]

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        await provider.loadActivityTypes(for: caree.id)
        XCTAssertEqual(provider.activityTypesByCaree[caree.id]?.count, 1)
        XCTAssertEqual(selectiveService.activityTypeFetchCount[caree.id], 1)

        selectiveService.activityTypesByCaree[caree.id]?.append(
            ActivityTypeSnapshot(
                name: "Medicine",
                icon: "💊",
                careeID: caree.id
            )
        )

        await provider.loadActivityTypes(for: caree.id)

        XCTAssertEqual(provider.activityTypesByCaree[caree.id]?.count, 2)
        XCTAssertEqual(selectiveService.activityTypeFetchCount[caree.id], 2)
    }

    func testLoadRecentActivitiesForceRefreshBypassesThrottle() async {
        let caree = CareeSnapshot(
            id: UUID(),
            name: "Jordan",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let activityTypeID = UUID()
        let selectiveService = MockSelectiveCloudKitService()
        selectiveService.recentActivitiesByCaree[caree.id] = [
            ActivitySnapshot(
                dateTime: Date(),
                activityTypeID: activityTypeID,
                careeID: caree.id,
                syncState: .synced
            )
        ]

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            perCareeRefreshThrottleInterval: 300
        )
        provider.carees = [caree]

        await provider.loadRecentActivities(for: caree.id)
        XCTAssertEqual(provider.recentActivitiesByCaree[caree.id]?.count, 1)
        XCTAssertEqual(selectiveService.recentActivityFetchCount[caree.id], 1)

        selectiveService.recentActivitiesByCaree[caree.id]?.append(
            ActivitySnapshot(
                dateTime: Date().addingTimeInterval(60),
                activityTypeID: activityTypeID,
                careeID: caree.id,
                syncState: .synced
            )
        )

        await provider.loadRecentActivities(for: caree.id)
        XCTAssertEqual(provider.recentActivitiesByCaree[caree.id]?.count, 1)
        XCTAssertEqual(selectiveService.recentActivityFetchCount[caree.id], 1, "Throttled refresh should not hit service")

        await provider.loadRecentActivities(for: caree.id, force: true)
        XCTAssertEqual(provider.recentActivitiesByCaree[caree.id]?.count, 2)
        XCTAssertEqual(selectiveService.recentActivityFetchCount[caree.id], 2, "Force refresh should bypass throttle")
    }
}

// MARK: - Test Doubles

final class MockSelectiveCloudKitService: SelectiveCloudKitService {
    var activityTypesByCaree: [UUID: [ActivityTypeSnapshot]] = [:]
    var recentActivitiesByCaree: [UUID: [ActivitySnapshot]] = [:]
    var activityTypeFetchCount: [UUID: Int] = [:]
    var recentActivityFetchCount: [UUID: Int] = [:]

    override func fetchActivityTypes(for careeID: UUID, isShared: Bool) async throws -> [ActivityTypeSnapshot] {
        activityTypeFetchCount[careeID, default: 0] += 1
        return activityTypesByCaree[careeID] ?? []
    }

    override func fetchRecentActivities(for careeID: UUID, isShared: Bool, hoursBack: TimeInterval) async throws -> [ActivitySnapshot] {
        recentActivityFetchCount[careeID, default: 0] += 1
        return recentActivitiesByCaree[careeID] ?? []
    }
}
