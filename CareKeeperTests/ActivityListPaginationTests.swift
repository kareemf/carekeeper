@testable import CareKeeper
import SwiftData
import XCTest

/// Tests for ActivityListView pagination logic
/// These tests verify the cursor-based pagination, filtering, and deduplication
/// strategies used to load activities in pages.
@MainActor
final class ActivityListPaginationTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var testCaree: Caree!
    var feedingType: ActivityType!
    var walkType: ActivityType!

    private let pageSize = 10

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

        // Create test caree with activity types
        testCaree = Caree(name: "Test Caree")
        modelContext.insert(testCaree)

        feedingType = ActivityType(name: "Feeding", icon: "🍼", caree: testCaree)
        modelContext.insert(feedingType)

        walkType = ActivityType(name: "Walk", icon: "🚶", caree: testCaree)
        modelContext.insert(walkType)

        try modelContext.save()
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        testCaree = nil
        feedingType = nil
        walkType = nil
    }

    // MARK: - Helper Methods

    /// Creates activities with sequential timestamps for predictable ordering
    private func createActivities(
        count: Int,
        type: ActivityType,
        startingFrom baseDate: Date = Date(),
        interval: TimeInterval = -60 // 1 minute apart, going backwards
    ) throws -> [Activity] {
        var activities: [Activity] = []
        for i in 0 ..< count {
            let date = baseDate.addingTimeInterval(Double(i) * interval)
            let activity = Activity(
                dateTime: date,
                notes: "Activity \(i)",
                activityType: type,
                caree: testCaree
            )
            modelContext.insert(activity)
            activities.append(activity)
        }
        try modelContext.save()
        return activities
    }

    /// Simulates the pagination fetch used by ActivityListView
    private func fetchPage(
        careeID: UUID,
        activityTypeID: UUID? = nil,
        cursorDate: Date? = nil,
        excludeIDs: Set<UUID> = [],
        limit: Int = 10
    ) throws -> [Activity] {
        let predicate: Predicate<Activity>

        if let typeID = activityTypeID, let cursorDate {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
                    && activity.activityType?.id == typeID
                    && activity.dateTime <= cursorDate
            }
        } else if let typeID = activityTypeID {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
                    && activity.activityType?.id == typeID
            }
        } else if let cursorDate {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
                    && activity.dateTime <= cursorDate
            }
        } else {
            predicate = #Predicate<Activity> { activity in
                activity.caree?.id == careeID
            }
        }

        var fetch = FetchDescriptor<Activity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dateTime, order: .reverse), SortDescriptor(\.id, order: .reverse)]
        )
        fetch.fetchLimit = limit + excludeIDs.count

        let page = try modelContext.fetch(fetch)

        // Filter out already-loaded activities (simulating deduplication)
        return page.filter { !excludeIDs.contains($0.id) }.prefix(limit).map { $0 }
    }

    // MARK: - Initial Page Tests

    func testInitialPageFetchesCorrectCount() throws {
        // Create more activities than page size
        _ = try createActivities(count: 25, type: feedingType)

        let page = try fetchPage(careeID: testCaree.id, limit: pageSize)

        XCTAssertEqual(page.count, pageSize, "Initial page should fetch exactly pageSize activities")
    }

    func testInitialPageOrderedByDateTimeDescending() throws {
        let activities = try createActivities(count: 15, type: feedingType)

        let page = try fetchPage(careeID: testCaree.id, limit: pageSize)

        // First activity in page should have the most recent date
        XCTAssertEqual(page.first?.id, activities.first?.id, "Most recent activity should be first")

        // Verify descending order
        for i in 0 ..< (page.count - 1) {
            XCTAssertGreaterThanOrEqual(
                page[i].dateTime,
                page[i + 1].dateTime,
                "Activities should be in descending date order"
            )
        }
    }

    func testInitialPageWithFewerThanPageSizeActivities() throws {
        _ = try createActivities(count: 5, type: feedingType)

        let page = try fetchPage(careeID: testCaree.id, limit: pageSize)

        XCTAssertEqual(page.count, 5, "Should return all activities when fewer than pageSize")
    }

    func testInitialPageWithNoActivities() throws {
        let page = try fetchPage(careeID: testCaree.id, limit: pageSize)

        XCTAssertTrue(page.isEmpty, "Should return empty array when no activities exist")
    }

    // MARK: - Cursor-Based Pagination Tests

    func testSecondPageUsesCursorDate() throws {
        _ = try createActivities(count: 25, type: feedingType)

        // Fetch first page
        let firstPage = try fetchPage(careeID: testCaree.id, limit: pageSize)
        let cursorDate = firstPage.last?.dateTime

        // Fetch second page using cursor
        let loadedIDs = Set(firstPage.map(\.id))
        let secondPage = try fetchPage(
            careeID: testCaree.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )

        XCTAssertEqual(secondPage.count, pageSize, "Second page should have pageSize activities")

        // Verify no overlap
        let secondPageIDs = Set(secondPage.map(\.id))
        XCTAssertTrue(loadedIDs.isDisjoint(with: secondPageIDs), "Pages should not have overlapping activities")
    }

    func testThirdPageContinuesPagination() throws {
        _ = try createActivities(count: 25, type: feedingType)

        // Fetch first page
        let firstPage = try fetchPage(careeID: testCaree.id, limit: pageSize)
        var loadedIDs = Set(firstPage.map(\.id))
        var cursorDate = firstPage.last?.dateTime

        // Fetch second page
        let secondPage = try fetchPage(
            careeID: testCaree.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )
        loadedIDs.formUnion(secondPage.map(\.id))
        cursorDate = secondPage.last?.dateTime

        // Fetch third page
        let thirdPage = try fetchPage(
            careeID: testCaree.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )

        XCTAssertEqual(thirdPage.count, 5, "Third page should have remaining 5 activities")
        XCTAssertTrue(loadedIDs.isDisjoint(with: Set(thirdPage.map(\.id))), "No duplicates across pages")
    }

    func testPaginationDetectsEndOfResults() throws {
        _ = try createActivities(count: 15, type: feedingType)

        // Fetch first page
        let firstPage = try fetchPage(careeID: testCaree.id, limit: pageSize)
        let loadedIDs = Set(firstPage.map(\.id))
        let cursorDate = firstPage.last?.dateTime

        // Fetch second page
        let secondPage = try fetchPage(
            careeID: testCaree.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )

        // When fewer than pageSize returned, we've reached the end
        let hasMorePages = secondPage.count >= pageSize
        XCTAssertFalse(hasMorePages, "Should detect end of results when count < pageSize")
    }

    // MARK: - Same DateTime Handling Tests

    func testHandlesActivitiesWithSameDateTime() throws {
        // Create activities with identical timestamps
        let sameTime = Date()
        var activities: [Activity] = []
        for i in 0 ..< 15 {
            let activity = Activity(
                dateTime: sameTime,
                notes: "Same time activity \(i)",
                activityType: feedingType,
                caree: testCaree
            )
            modelContext.insert(activity)
            activities.append(activity)
        }
        try modelContext.save()

        // Fetch first page
        let firstPage = try fetchPage(careeID: testCaree.id, limit: pageSize)
        let loadedIDs = Set(firstPage.map(\.id))
        let cursorDate = firstPage.last?.dateTime

        // Fetch second page - should use ID-based deduplication
        let secondPage = try fetchPage(
            careeID: testCaree.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )

        XCTAssertEqual(secondPage.count, 5, "Should get remaining activities despite same dateTime")
        XCTAssertTrue(loadedIDs.isDisjoint(with: Set(secondPage.map(\.id))), "No duplicates")
    }

    func testDeduplicationPreventsDuplicatesWithSameTimestamp() throws {
        // Create activities with same timestamp
        let sameTime = Date()
        for i in 0 ..< 20 {
            let activity = Activity(
                dateTime: sameTime,
                notes: "Activity \(i)",
                activityType: feedingType,
                caree: testCaree
            )
            modelContext.insert(activity)
        }
        try modelContext.save()

        var allLoadedIDs = Set<UUID>()
        var cursorDate: Date? = nil

        // Load all pages
        while true {
            let page = try fetchPage(
                careeID: testCaree.id,
                cursorDate: cursorDate,
                excludeIDs: allLoadedIDs,
                limit: pageSize
            )

            if page.isEmpty { break }

            // Verify no duplicates
            for activity in page {
                XCTAssertFalse(allLoadedIDs.contains(activity.id), "Should not have duplicate activity")
                allLoadedIDs.insert(activity.id)
            }

            cursorDate = page.last?.dateTime

            if page.count < pageSize { break }
        }

        XCTAssertEqual(allLoadedIDs.count, 20, "Should have loaded all 20 activities without duplicates")
    }

    // MARK: - Activity Type Filtering Tests

    func testFilterByActivityType() throws {
        _ = try createActivities(count: 15, type: feedingType)
        _ = try createActivities(count: 10, type: walkType)

        let page = try fetchPage(
            careeID: testCaree.id,
            activityTypeID: feedingType.id,
            limit: pageSize
        )

        XCTAssertEqual(page.count, pageSize, "Should return pageSize feeding activities")
        XCTAssertTrue(
            page.allSatisfy { $0.activityType?.id == feedingType.id },
            "All activities should be feeding type"
        )
    }

    func testFilterByActivityTypeWithPagination() throws {
        _ = try createActivities(count: 25, type: feedingType)
        _ = try createActivities(count: 10, type: walkType)

        // First page of feeding activities
        let firstPage = try fetchPage(
            careeID: testCaree.id,
            activityTypeID: feedingType.id,
            limit: pageSize
        )
        let loadedIDs = Set(firstPage.map(\.id))
        let cursorDate = firstPage.last?.dateTime

        // Second page of feeding activities
        let secondPage = try fetchPage(
            careeID: testCaree.id,
            activityTypeID: feedingType.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )

        XCTAssertEqual(secondPage.count, pageSize, "Second page should have pageSize activities")
        XCTAssertTrue(
            secondPage.allSatisfy { $0.activityType?.id == feedingType.id },
            "All activities should be feeding type"
        )
        XCTAssertTrue(loadedIDs.isDisjoint(with: Set(secondPage.map(\.id))), "No duplicates across pages")
    }

    func testFilterByActivityTypeWithNoMatches() throws {
        _ = try createActivities(count: 10, type: feedingType)

        let page = try fetchPage(
            careeID: testCaree.id,
            activityTypeID: walkType.id,
            limit: pageSize
        )

        XCTAssertTrue(page.isEmpty, "Should return empty when no activities match filter")
    }

    func testSwitchingFilterResetsResults() throws {
        _ = try createActivities(count: 15, type: feedingType)
        _ = try createActivities(count: 15, type: walkType)

        // Fetch feeding activities
        let feedingPage = try fetchPage(
            careeID: testCaree.id,
            activityTypeID: feedingType.id,
            limit: pageSize
        )

        // Switch to walk filter (simulates resetting pagination state)
        let walkPage = try fetchPage(
            careeID: testCaree.id,
            activityTypeID: walkType.id,
            limit: pageSize
        )

        XCTAssertEqual(feedingPage.count, pageSize)
        XCTAssertEqual(walkPage.count, pageSize)
        XCTAssertTrue(
            feedingPage.allSatisfy { $0.activityType?.id == feedingType.id },
            "Feeding page should only have feeding activities"
        )
        XCTAssertTrue(
            walkPage.allSatisfy { $0.activityType?.id == walkType.id },
            "Walk page should only have walk activities"
        )
    }

    // MARK: - Caree Isolation Tests

    func testOnlyFetchesActivitiesForSpecificCaree() throws {
        // Create another caree with activities
        let otherCaree = Caree(name: "Other Caree")
        modelContext.insert(otherCaree)
        let otherType = ActivityType(name: "Other", caree: otherCaree)
        modelContext.insert(otherType)

        _ = try createActivities(count: 10, type: feedingType) // For testCaree
        for i in 0 ..< 10 {
            let activity = Activity(
                dateTime: Date().addingTimeInterval(Double(i) * -60),
                notes: "Other activity \(i)",
                activityType: otherType,
                caree: otherCaree
            )
            modelContext.insert(activity)
        }
        try modelContext.save()

        let page = try fetchPage(careeID: testCaree.id, limit: 20)

        XCTAssertEqual(page.count, 10, "Should only fetch activities for specified caree")
        XCTAssertTrue(
            page.allSatisfy { $0.caree?.id == testCaree.id },
            "All activities should belong to testCaree"
        )
    }

    // MARK: - ID-Based Fetch Tests (for fresh object retrieval)

    func testFetchActivitiesByIDs() throws {
        let activities = try createActivities(count: 10, type: feedingType)
        let idsToFetch = Array(activities.prefix(5).map(\.id))

        let predicate = #Predicate<Activity> { activity in
            idsToFetch.contains(activity.id)
        }
        var fetch = FetchDescriptor<Activity>(predicate: predicate)
        fetch.fetchLimit = idsToFetch.count

        let fetched = try modelContext.fetch(fetch)

        XCTAssertEqual(fetched.count, 5, "Should fetch exactly 5 activities by ID")

        // Verify we got the right activities
        let fetchedIDs = Set(fetched.map(\.id))
        XCTAssertEqual(fetchedIDs, Set(idsToFetch), "Should fetch the correct activities")
    }

    func testFetchByIDsPreservesOrder() throws {
        let activities = try createActivities(count: 10, type: feedingType)
        let orderedIDs = activities.map(\.id)

        let predicate = #Predicate<Activity> { activity in
            orderedIDs.contains(activity.id)
        }
        var fetch = FetchDescriptor<Activity>(predicate: predicate)
        fetch.fetchLimit = orderedIDs.count

        let fetched = try modelContext.fetch(fetch)

        // Reconstruct order from IDs
        let idToActivity = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        let orderedFetched = orderedIDs.compactMap { idToActivity[$0] }

        XCTAssertEqual(orderedFetched.count, activities.count, "Should preserve all activities")
        for (original, fetched) in zip(activities, orderedFetched) {
            XCTAssertEqual(original.id, fetched.id, "Order should be preserved")
        }
    }

    // MARK: - Edge Cases

    func testPaginationWithExactlyPageSizeActivities() throws {
        _ = try createActivities(count: pageSize, type: feedingType)

        let firstPage = try fetchPage(careeID: testCaree.id, limit: pageSize)
        let loadedIDs = Set(firstPage.map(\.id))
        let cursorDate = firstPage.last?.dateTime

        let secondPage = try fetchPage(
            careeID: testCaree.id,
            cursorDate: cursorDate,
            excludeIDs: loadedIDs,
            limit: pageSize
        )

        XCTAssertEqual(firstPage.count, pageSize, "First page should be full")
        XCTAssertTrue(secondPage.isEmpty, "Second page should be empty")
    }

    func testPaginationWithOneActivity() throws {
        _ = try createActivities(count: 1, type: feedingType)

        let page = try fetchPage(careeID: testCaree.id, limit: pageSize)

        XCTAssertEqual(page.count, 1, "Should return single activity")
    }

    func testPaginationWithLargeDataset() throws {
        // Create a larger dataset to stress test
        _ = try createActivities(count: 150, type: feedingType)

        var allLoadedIDs = Set<UUID>()
        var cursorDate: Date? = nil
        var pageCount = 0

        while true {
            let page = try fetchPage(
                careeID: testCaree.id,
                cursorDate: cursorDate,
                excludeIDs: allLoadedIDs,
                limit: pageSize
            )

            if page.isEmpty { break }

            pageCount += 1
            allLoadedIDs.formUnion(page.map(\.id))
            cursorDate = page.last?.dateTime

            if page.count < pageSize { break }
        }

        XCTAssertEqual(allLoadedIDs.count, 150, "Should load all activities")
        XCTAssertEqual(pageCount, 15, "Should take 15 pages to load 150 activities with pageSize 10")
    }
}
