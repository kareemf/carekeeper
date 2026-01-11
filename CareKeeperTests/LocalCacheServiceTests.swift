@testable import CareKeeper
import SwiftData
import XCTest

@MainActor
final class LocalCacheServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var cacheService: LocalCacheService!

    override func setUp() async throws {
        let schema = Schema([
            Caree.self,
            ActivityType.self,
            Activity.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        modelContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )

        modelContext = ModelContext(modelContainer)
        cacheService = LocalCacheService(modelContext: modelContext)
    }

    override func tearDown() async throws {
        cacheService = nil
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Immediate Refresh Tests

    func testRefreshImmediatelyUpdatesPublishedProperties() async throws {
        // Given: A caree in the model context
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        caree.isShared = false
        modelContext.insert(caree)
        try modelContext.save()

        // When: Immediate refresh is called
        await cacheService.refreshImmediately(reason: "test")

        // Then: Published properties should be updated
        XCTAssertEqual(cacheService.myCarees.count, 1, "Should have 1 owned caree")
        XCTAssertEqual(cacheService.myCarees.first?.name, "Test Caree")
    }

    func testRefreshImmediatelyWithSharedCaree() async throws {
        // Given: A shared caree in the model context
        let caree = Caree(name: "Shared Caree", listOrder: 0)
        caree.isOwned = false
        caree.isShared = true
        modelContext.insert(caree)
        try modelContext.save()

        // When: Immediate refresh is called
        await cacheService.refreshImmediately(reason: "test")

        // Then: Published properties should be updated
        XCTAssertEqual(cacheService.sharedCarees.count, 1, "Should have 1 shared caree")
        XCTAssertEqual(cacheService.sharedCarees.first?.name, "Shared Caree")
    }

    func testRefreshImmediatelyWithMultipleCarees() async throws {
        // Given: Multiple carees with different ownership
        let owned1 = Caree(name: "Owned 1", listOrder: 0)
        owned1.isOwned = true
        owned1.isShared = false

        let owned2 = Caree(name: "Owned 2", listOrder: 1)
        owned2.isOwned = true
        owned2.isShared = false

        let shared1 = Caree(name: "Shared 1", listOrder: 0)
        shared1.isOwned = false
        shared1.isShared = true

        modelContext.insert(owned1)
        modelContext.insert(owned2)
        modelContext.insert(shared1)
        try modelContext.save()

        // When: Immediate refresh is called
        await cacheService.refreshImmediately(reason: "test")

        // Then: Should have correct counts
        XCTAssertEqual(cacheService.myCarees.count, 2, "Should have 2 owned carees")
        XCTAssertEqual(cacheService.sharedCarees.count, 1, "Should have 1 shared caree")
    }

    func testRefreshImmediatelyDoesNotDebounce() async throws {
        // Given: A caree in the model context
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        caree.isShared = false
        modelContext.insert(caree)
        try modelContext.save()

        // When: Immediate refresh is called
        let startTime = Date()
        await cacheService.refreshImmediately(reason: "test")
        let endTime = Date()

        // Then: Should complete quickly (no 0.25s debounce delay)
        let elapsed = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 0.2, "Immediate refresh should complete in <200ms (no debounce)")

        // And: Published properties should be updated
        XCTAssertEqual(cacheService.myCarees.count, 1)
    }

    // MARK: - Missing Cache Entry Tests

    func testCacheCareeWhenMissing() async throws {
        // Given: A caree not in cache
        let caree = Caree(name: "New Caree", listOrder: 0)
        caree.isOwned = true

        // When: Caching the caree
        try await cacheService.cacheCaree(caree, isShared: false)

        // Then: Caree should be retrievable from cache
        let cached = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNotNil(cached, "Caree should be in cache")
        XCTAssertEqual(cached?.name, "New Caree")
        XCTAssertTrue(cached?.isOwned ?? false, "Should be marked as owned")
        XCTAssertFalse(cached?.isShared ?? true, "Should not be marked as shared")
    }

    func testCacheActivityTypeWhenMissing() async throws {
        // Given: A caree in cache
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)
        try modelContext.save()

        try await cacheService.cacheCaree(caree, isShared: false)
        await cacheService.refreshImmediately(reason: "setup")

        guard let cachedCaree = cacheService.getCachedCaree(id: caree.id) else {
            XCTFail("Caree should be in cache")
            return
        }

        // And: An activity type not in cache
        let activityType = ActivityType(name: "Feeding", icon: "🍼", listOrder: 0)

        // When: Caching the activity type
        try await cacheService.cacheActivityType(activityType, for: cachedCaree)
        await cacheService.refreshImmediately(reason: "test")

        // Then: Activity type should be in cache
        let cachedTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
        XCTAssertEqual(cachedTypes.count, 1, "Should have 1 activity type")
        XCTAssertEqual(cachedTypes.first?.name, "Feeding")
    }

    func testCacheActivityWhenParentsPresent() async throws {
        // Given: A caree and activity type in cache
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree, listOrder: 0)
        modelContext.insert(activityType)

        try modelContext.save()

        try await cacheService.cacheCaree(caree, isShared: false)
        await cacheService.refreshImmediately(reason: "setup")

        guard let cachedCaree = cacheService.getCachedCaree(id: caree.id) else {
            XCTFail("Caree should be in cache")
            return
        }

        // And: An activity not in cache
        let activity = Activity(dateTime: Date(), notes: "Test activity")

        // When: Caching the activity
        try await cacheService.cacheActivity(activity, for: cachedCaree, activityTypeID: activityType.id)
        await cacheService.refreshImmediately(reason: "test")

        // Then: Activity should be in cache
        let cachedActivities = cacheService.getCachedActivities(for: cachedCaree)
        XCTAssertEqual(cachedActivities.count, 1, "Should have 1 activity")
        XCTAssertEqual(cachedActivities.first?.notes, "Test activity")
    }

    // MARK: - Scheduled vs Immediate Refresh Tests

    func testScheduledRefreshHasDebounce() async throws {
        // Given: A caree in the model context
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)
        try modelContext.save()

        // When: Scheduled refresh is called
        cacheService.scheduleRefresh(reason: "test")

        // Then: Published properties should NOT be updated immediately (debounced)
        XCTAssertEqual(cacheService.myCarees.count, 0, "Should not be updated immediately")

        // Wait for debounce to complete (0.25s + buffer)
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // Then: Published properties should now be updated
        XCTAssertEqual(cacheService.myCarees.count, 1, "Should be updated after debounce")
    }

    func testImmediateRefreshBypassesDebounce() async throws {
        // Given: A caree in the model context
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)
        try modelContext.save()

        // When: Immediate refresh is called
        await cacheService.refreshImmediately(reason: "test")

        // Then: Published properties should be updated immediately
        XCTAssertEqual(cacheService.myCarees.count, 1, "Should be updated immediately")
    }

    // MARK: - Integration Tests

    func testColdStartScenario() async throws {
        // Simulates the cold start issue: cache is empty when creating an activity

        // Given: Empty cache (cache service initialized but no data loaded)
        XCTAssertEqual(cacheService.myCarees.count, 0, "Cache should start empty")

        // And: A caree and activity type exist in CloudKit (simulated by creating them)
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true

        let activityType = ActivityType(name: "Feeding", icon: "🍼", listOrder: 0)

        // When: Handling activity creation with missing cache entries
        // (This simulates what CloudKitDataService.createActivity does)

        // Step 1: Check if caree is in cache (it's not)
        var cachedCaree = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNil(cachedCaree, "Caree should not be in cache initially")

        // Step 2: Cache the caree
        try await cacheService.cacheCaree(caree, isShared: false)
        cachedCaree = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNotNil(cachedCaree, "Caree should now be in cache")

        // Step 3: Check if activity type is in cache (it's not)
        var cachedTypes = cacheService.getCachedActivityTypes(for: cachedCaree!)
        XCTAssertEqual(cachedTypes.count, 0, "ActivityType should not be in cache initially")

        // Step 4: Cache the activity type
        try await cacheService.cacheActivityType(activityType, for: cachedCaree!)
        cachedTypes = cacheService.getCachedActivityTypes(for: cachedCaree!)
        XCTAssertEqual(cachedTypes.count, 1, "ActivityType should now be in cache")

        // Step 5: Cache the activity
        let activity = Activity(dateTime: Date(), notes: "First activity")
        try await cacheService.cacheActivity(activity, for: cachedCaree!, activityTypeID: activityType.id)

        // Step 6: Immediate refresh (hot operation)
        await cacheService.refreshImmediately(reason: "createActivity")

        // Then: All data should be accessible via published properties
        XCTAssertEqual(cacheService.myCarees.count, 1, "Should have 1 caree")
        XCTAssertEqual(cacheService.myCarees.first?.name, "Test Caree")

        let finalCaree = cacheService.myCarees.first!
        XCTAssertEqual(finalCaree.activityTypes?.count, 1, "Should have 1 activity type")
        XCTAssertEqual(finalCaree.activities?.count, 1, "Should have 1 activity")
    }

    // MARK: - Background Refresh Preservation Tests

    func testBackgroundRefreshPreservesLocalActivity() async throws {
        // Simulates the race condition: background refresh completes while user is creating an activity

        // Given: A caree already in cache (from an earlier refresh)
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree, listOrder: 0)
        modelContext.insert(activityType)

        try modelContext.save()

        try await cacheService.cacheCaree(caree, isShared: false)
        await cacheService.refreshImmediately(reason: "setup")

        guard let cachedCaree = cacheService.getCachedCaree(id: caree.id) else {
            XCTFail("Caree should be in cache")
            return
        }

        // When: Background refresh starts
        cacheService.beginBackgroundRefresh()

        // And: User creates an activity during the refresh
        let localActivity = Activity(dateTime: Date(), notes: "User created during refresh")
        try await cacheService.cacheActivity(localActivity, for: cachedCaree, activityTypeID: activityType.id)
        await cacheService.refreshImmediately(reason: "createActivity")

        // And: Background refresh completes with stale CloudKit data (empty activities list)
        try await cacheService.replaceCaree(
            caree,
            activityTypes: [activityType],
            activities: [], // Empty - represents stale CloudKit snapshot
            activityTypeIDsByActivity: [:]
        )
        cacheService.endBackgroundRefresh()

        await cacheService.refreshImmediately(reason: "backgroundRefreshComplete")

        // Then: The locally-created activity should still be in cache
        let finalCaree = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNotNil(finalCaree, "Caree should still be in cache")
        XCTAssertEqual(finalCaree?.activities?.count, 1, "Should preserve local activity")
        XCTAssertEqual(finalCaree?.activities?.first?.notes, "User created during refresh")
    }

    func testBackgroundRefreshPreservesLocalActivityType() async throws {
        // Given: A caree already in cache
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)
        try modelContext.save()

        try await cacheService.cacheCaree(caree, isShared: false)
        await cacheService.refreshImmediately(reason: "setup")

        guard let cachedCaree = cacheService.getCachedCaree(id: caree.id) else {
            XCTFail("Caree should be in cache")
            return
        }

        // When: Background refresh starts
        cacheService.beginBackgroundRefresh()

        // And: User creates an activity type during the refresh
        let localActivityType = ActivityType(name: "Sleep", icon: "😴", listOrder: 0)
        try await cacheService.cacheActivityType(localActivityType, for: cachedCaree)
        await cacheService.refreshImmediately(reason: "createActivityType")

        // And: Background refresh completes with stale CloudKit data (empty activity types)
        try await cacheService.replaceCaree(
            caree,
            activityTypes: [], // Empty - represents stale CloudKit snapshot
            activities: [],
            activityTypeIDsByActivity: [:]
        )
        cacheService.endBackgroundRefresh()

        await cacheService.refreshImmediately(reason: "backgroundRefreshComplete")

        // Then: The locally-created activity type should still be in cache
        let finalCaree = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNotNil(finalCaree, "Caree should still be in cache")
        XCTAssertEqual(finalCaree?.activityTypes?.count, 1, "Should preserve local activity type")
        XCTAssertEqual(finalCaree?.activityTypes?.first?.name, "Sleep")
    }

    func testBackgroundRefreshMergesCloudKitAndLocalRecords() async throws {
        // Given: A caree with an existing activity type in cache
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)

        let cloudActivityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree, listOrder: 0)
        modelContext.insert(cloudActivityType)

        let cloudActivity = Activity(dateTime: Date().addingTimeInterval(-3600), notes: "From CloudKit")
        cloudActivity.activityType = cloudActivityType
        cloudActivity.caree = caree
        modelContext.insert(cloudActivity)

        try modelContext.save()

        try await cacheService.cacheCaree(caree, isShared: false)
        await cacheService.refreshImmediately(reason: "setup")

        guard let cachedCaree = cacheService.getCachedCaree(id: caree.id) else {
            XCTFail("Caree should be in cache")
            return
        }

        // When: Background refresh starts
        cacheService.beginBackgroundRefresh()

        // And: User creates a new activity during the refresh
        let localActivity = Activity(dateTime: Date(), notes: "Created locally")
        try await cacheService.cacheActivity(localActivity, for: cachedCaree, activityTypeID: cloudActivityType.id)
        await cacheService.refreshImmediately(reason: "createActivity")

        // And: Background refresh completes with CloudKit data (only has the old activity)
        try await cacheService.replaceCaree(
            caree,
            activityTypes: [cloudActivityType],
            activities: [cloudActivity], // Only the old activity from CloudKit
            activityTypeIDsByActivity: [cloudActivity.id: cloudActivityType.id]
        )
        cacheService.endBackgroundRefresh()

        await cacheService.refreshImmediately(reason: "backgroundRefreshComplete")

        // Then: Both activities should be in cache (merged)
        let finalCaree = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNotNil(finalCaree, "Caree should still be in cache")
        XCTAssertEqual(finalCaree?.activities?.count, 2, "Should have both CloudKit and local activities")

        let activityNotes = Set(finalCaree?.activities?.compactMap { $0.notes } ?? [])
        XCTAssertTrue(activityNotes.contains("From CloudKit"), "Should have CloudKit activity")
        XCTAssertTrue(activityNotes.contains("Created locally"), "Should have local activity")
    }

    func testBackgroundRefreshWithoutLocalChanges() async throws {
        // Verifies normal background refresh behavior when no local changes are made

        // Given: A caree with activities in cache
        let caree = Caree(name: "Test Caree", listOrder: 0)
        caree.isOwned = true
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree, listOrder: 0)
        modelContext.insert(activityType)

        let oldActivity = Activity(dateTime: Date().addingTimeInterval(-3600), notes: "Old")
        oldActivity.activityType = activityType
        oldActivity.caree = caree
        modelContext.insert(oldActivity)

        try modelContext.save()

        try await cacheService.cacheCaree(caree, isShared: false)
        await cacheService.refreshImmediately(reason: "setup")

        // When: Background refresh runs without any local changes
        cacheService.beginBackgroundRefresh()

        let newActivity = Activity(dateTime: Date(), notes: "New from CloudKit")
        newActivity.activityType = activityType
        newActivity.caree = caree

        try await cacheService.replaceCaree(
            caree,
            activityTypes: [activityType],
            activities: [oldActivity, newActivity], // Updated list from CloudKit
            activityTypeIDsByActivity: [
                oldActivity.id: activityType.id,
                newActivity.id: activityType.id
            ]
        )
        cacheService.endBackgroundRefresh()

        await cacheService.refreshImmediately(reason: "backgroundRefreshComplete")

        // Then: Cache should reflect CloudKit data (no local changes to preserve)
        let finalCaree = cacheService.getCachedCaree(id: caree.id)
        XCTAssertNotNil(finalCaree, "Caree should be in cache")
        XCTAssertEqual(finalCaree?.activities?.count, 2, "Should have both activities from CloudKit")

        let activityNotes = Set(finalCaree?.activities?.compactMap { $0.notes } ?? [])
        XCTAssertTrue(activityNotes.contains("Old"), "Should have old activity")
        XCTAssertTrue(activityNotes.contains("New from CloudKit"), "Should have new activity from CloudKit")
    }
}
