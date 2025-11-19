@testable import CareKeeper
import XCTest

@MainActor
final class WatchDataProviderTests: XCTestCase {
    func testLoadRecentActivitiesAppliesReminderMetadataForOwnedCaree() async {
        let caree = CareeSnapshot(
            id: UUID(),
            name: "Taylor",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let activityID = UUID()
        let activityTypeID = UUID()
        let selectiveService = MockSelectiveCloudKitService()
        selectiveService.recentActivitiesByCaree[caree.id] = [
            ActivitySnapshot(
                id: activityID,
                dateTime: Date(),
                notes: nil,
                quantity: nil,
                latitude: nil,
                longitude: nil,
                activityTypeID: activityTypeID,
                careeID: caree.id,
                dateCreated: Date(),
                reminderIdentifier: nil,
                reminderDueDate: nil,
                reminderSource: nil,
                syncState: .synced
            ),
        ]

        let reminderStore = MockReminderMetadataStore()
        reminderStore.fetchResults[activityID] = ActivityReminderMetadata(
            activityID: activityID,
            reminderDueDate: Date().addingTimeInterval(300),
            reminderSource: .phone,
            unNotificationIdentifier: "owned-reminder"
        )

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        await provider.loadRecentActivities(for: caree.id, force: true)

        let fetched = provider.recentActivitiesByCaree[caree.id]?.first
        XCTAssertEqual(fetched?.reminderIdentifier, "owned-reminder")
        XCTAssertEqual(reminderStore.fetchRequests.first?.sorted(), [activityID])
    }

    func testLoadRecentActivitiesAppliesReminderMetadataForSharedCaree() async {
        let caree = CareeSnapshot(
            id: UUID(),
            name: "Jordan",
            imageData: nil,
            isShared: true,
            listOrder: 0,
            dateCreated: Date()
        )

        let activityID = UUID()
        let activityTypeID = UUID()
        let selectiveService = MockSelectiveCloudKitService()
        selectiveService.recentActivitiesByCaree[caree.id] = [
            ActivitySnapshot(
                id: activityID,
                dateTime: Date(),
                notes: "Shared",
                quantity: nil,
                latitude: nil,
                longitude: nil,
                activityTypeID: activityTypeID,
                careeID: caree.id,
                dateCreated: Date(),
                reminderIdentifier: nil,
                reminderDueDate: nil,
                reminderSource: nil,
                syncState: .synced
            ),
        ]

        let reminderStore = MockReminderMetadataStore()
        reminderStore.fetchResults[activityID] = ActivityReminderMetadata(
            activityID: activityID,
            reminderDueDate: Date().addingTimeInterval(600),
            reminderSource: .watch,
            unNotificationIdentifier: "shared-reminder"
        )

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        await provider.loadRecentActivities(for: caree.id, force: true)

        let fetched = provider.recentActivitiesByCaree[caree.id]?.first
        XCTAssertEqual(fetched?.reminderIdentifier, "shared-reminder")
        XCTAssertEqual(reminderStore.fetchRequests.first?.sorted(), [activityID])
    }

    func testLoadRecentActivitiesSchedulesWatchReminderWhenMissing() async {
        let caree = CareeSnapshot(
            id: UUID(),
            name: "Emerson",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let activityID = UUID()
        let activityTypeID = UUID()
        let selectiveService = MockSelectiveCloudKitService()
        selectiveService.recentActivitiesByCaree[caree.id] = [
            ActivitySnapshot(
                id: activityID,
                dateTime: Date(),
                notes: "Check vitals",
                quantity: nil,
                latitude: nil,
                longitude: nil,
                activityTypeID: activityTypeID,
                careeID: caree.id,
                dateCreated: Date(),
                reminderIdentifier: nil,
                reminderDueDate: nil,
                reminderSource: nil,
                syncState: .synced
            ),
        ]
        selectiveService.activityTypesByCaree[caree.id] = [
            ActivityTypeSnapshot(name: "Vitals", icon: "waveform.path.ecg", careeID: caree.id),
        ]

        let reminderStore = MockReminderMetadataStore()
        reminderStore.fetchResults[activityID] = ActivityReminderMetadata(
            activityID: activityID,
            reminderDueDate: Date().addingTimeInterval(600),
            reminderSource: .phone,
            ekReminderIdentifier: "phone-id",
            unNotificationIdentifier: nil
        )
        let syncCoordinator = MockReminderSyncCoordinator()
        syncCoordinator.result[activityID] = "watch-generated"

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            reminderSyncCoordinator: syncCoordinator,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        await provider.loadRecentActivities(for: caree.id, force: true)

        let fetched = provider.recentActivitiesByCaree[caree.id]?.first
        XCTAssertEqual(fetched?.reminderIdentifier, "watch-generated")
        XCTAssertEqual(syncCoordinator.lastOwner, .watch)
        XCTAssertEqual(syncCoordinator.receivedPayloads.first?.activityID, activityID)
    }

    func testTrackActivitySavesReminderMetadata() async {
        let careeID = UUID()
        let activityTypeID = UUID()
        let caree = CareeSnapshot(
            id: careeID,
            name: "Jordan",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let selectiveService = MockSelectiveCloudKitService()
        let reminderStore = MockReminderMetadataStore()
        let saveExpectation = expectation(description: "save metadata")
        reminderStore.saveExpectation = saveExpectation

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        var activity = ActivitySnapshot(
            dateTime: Date(),
            notes: "Check temperature",
            quantity: nil,
            latitude: nil,
            longitude: nil,
            activityTypeID: activityTypeID,
            careeID: careeID,
            dateCreated: Date()
        )
        activity.reminderIdentifier = "new-reminder"
        activity.reminderDueDate = Date().addingTimeInterval(300)
        activity.reminderSourceRawValue = ReminderSource.current.rawValue

        await provider.trackActivity(activity)
        await fulfillment(of: [saveExpectation], timeout: 1.0)

        XCTAssertEqual(reminderStore.savedMetadata[activity.id]?.reminderIdentifier, "new-reminder")
    }

    func testUpdateActivitySavesReminderMetadata() async {
        let careeID = UUID()
        let activityTypeID = UUID()
        let caree = CareeSnapshot(
            id: careeID,
            name: "Avery",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let selectiveService = MockSelectiveCloudKitService()
        let reminderStore = MockReminderMetadataStore()
        let saveExpectation = expectation(description: "update reminder")
        reminderStore.saveExpectation = saveExpectation

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        var activity = ActivitySnapshot(
            dateTime: Date(),
            notes: "Follow-up",
            quantity: nil,
            latitude: nil,
            longitude: nil,
            activityTypeID: activityTypeID,
            careeID: careeID,
            dateCreated: Date()
        )
        activity.reminderIdentifier = "existing-reminder"
        activity.reminderDueDate = Date().addingTimeInterval(900)
        activity.reminderSourceRawValue = ReminderSource.current.rawValue

        await provider.updateActivity(activity)
        await fulfillment(of: [saveExpectation], timeout: 1.0)

        XCTAssertEqual(reminderStore.savedMetadata[activity.id]?.reminderIdentifier, "existing-reminder")
    }

    func testDeleteActivityRemovesReminderMetadata() async {
        let careeID = UUID()
        let activityTypeID = UUID()
        let caree = CareeSnapshot(
            id: careeID,
            name: "Riley",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let selectiveService = MockSelectiveCloudKitService()
        let reminderStore = MockReminderMetadataStore()
        let deleteExpectation = expectation(description: "delete reminder")
        reminderStore.deleteExpectation = deleteExpectation

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        let activity = ActivitySnapshot(
            dateTime: Date(),
            notes: "Remove reminder",
            quantity: nil,
            latitude: nil,
            longitude: nil,
            activityTypeID: activityTypeID,
            careeID: careeID,
            dateCreated: Date(),
            reminderIdentifier: "delete-id",
            reminderDueDate: Date(),
            reminderSource: ReminderSource.current,
            syncState: .synced
        )

        await provider.deleteActivity(activity)
        await fulfillment(of: [deleteExpectation], timeout: 1.0)

        XCTAssertTrue(reminderStore.deletedActivityIDs.contains(activity.id))
    }

    func testUpdateActivityClearsReminderMetadataWhenRemoved() async {
        let careeID = UUID()
        let activityTypeID = UUID()
        let caree = CareeSnapshot(
            id: careeID,
            name: "Morgan",
            imageData: nil,
            isShared: false,
            listOrder: 0,
            dateCreated: Date()
        )

        let selectiveService = MockSelectiveCloudKitService()
        let reminderStore = MockReminderMetadataStore()
        let deleteExpectation = expectation(description: "cleared reminder metadata")
        reminderStore.deleteExpectation = deleteExpectation

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
            perCareeRefreshThrottleInterval: 0
        )
        provider.carees = [caree]

        let activity = ActivitySnapshot(
            dateTime: Date(),
            notes: "Toggle reminder off",
            quantity: nil,
            latitude: nil,
            longitude: nil,
            activityTypeID: activityTypeID,
            careeID: careeID,
            dateCreated: Date(),
            reminderIdentifier: nil,
            reminderDueDate: nil,
            reminderSource: nil,
            syncState: .synced
        )

        await provider.updateActivity(activity)
        await fulfillment(of: [deleteExpectation], timeout: 1.0)

        XCTAssertTrue(reminderStore.deletedActivityIDs.contains(activity.id))
    }
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
            ),
        ]

        let reminderStore = MockReminderMetadataStore()
        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: reminderStore,
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
            ),
        ]

        let provider = WatchDataProvider(
            cacheService: WatchCacheService(),
            selectiveService: selectiveService,
            reminderMetadataStore: MockReminderMetadataStore(),
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

@MainActor
final class MockSelectiveCloudKitService: SelectiveCloudKitServiceProtocol {
    var activityTypesByCaree: [UUID: [ActivityTypeSnapshot]] = [:]
    var recentActivitiesByCaree: [UUID: [ActivitySnapshot]] = [:]
    var activityTypeFetchCount: [UUID: Int] = [:]
    var recentActivityFetchCount: [UUID: Int] = [:]

    func fetchAllCarees(includeImages: Bool) async throws -> [CareeSnapshot] { [] }

    func fetchCareeImage(for careeID: UUID, zoneName: String, zoneOwnerName: String?, isShared: Bool) async throws -> Data? {
        nil
    }

    func fetchActivityTypes(for careeID: UUID, isShared: Bool) async throws -> [ActivityTypeSnapshot] {
        activityTypeFetchCount[careeID, default: 0] += 1
        return activityTypesByCaree[careeID] ?? []
    }

    func fetchRecentActivities(
        for careeID: UUID,
        activityTypeID: UUID? = nil,
        isShared: Bool,
        hoursBack: TimeInterval? = nil
    ) async throws -> [ActivitySnapshot] {
        recentActivityFetchCount[careeID, default: 0] += 1
        return recentActivitiesByCaree[careeID] ?? []
    }

    func fetchActivityTypeCount(for careeID: UUID, isShared: Bool) async throws -> Int {
        activityTypesByCaree[careeID]?.count ?? 0
    }

    func createActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws -> ActivitySnapshot {
        activity
    }

    func updateActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws -> ActivitySnapshot {
        activity
    }

    func deleteActivity(_ activity: ActivitySnapshot, isShared: Bool) async throws {}
}

final class MockReminderSyncCoordinator: ReminderSyncCoordinating {
    var lastOwner: ReminderSource?
    var receivedPayloads: [ReminderSyncPayload] = []
    var result: [UUID: String] = [:]

    func synchronize(owner: ReminderSource, payloads: [ReminderSyncPayload]) async -> [UUID: String] {
        lastOwner = owner
        receivedPayloads = payloads
        return result
    }
}
