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
}
