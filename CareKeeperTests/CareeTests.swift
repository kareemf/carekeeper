@testable import CareKeeper
import SwiftData
import XCTest

@MainActor
final class CareeTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

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
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }

    // MARK: - Initialization Tests

    func testCareeInitialization() {
        let caree = Caree(name: "Test Caree")

        XCTAssertNotNil(caree.id, "Caree should have a UUID")
        XCTAssertEqual(caree.name, "Test Caree", "Name should be set correctly")
        XCTAssertNil(caree.image, "Image should be nil by default")
        XCTAssertEqual(caree.listOrder, 0, "List order should default to 0")
        XCTAssertNotNil(caree.dateCreated, "Date created should be set")
        XCTAssertTrue(caree.activityTypes?.isEmpty ?? true, "Activity types should be empty initially")
        XCTAssertTrue(caree.activities?.isEmpty ?? true, "Activities should be empty initially")
    }

    func testCareeInitializationWithImage() {
        let imageData = Data([0x01, 0x02, 0x03])
        let caree = Caree(name: "Test Caree", image: imageData, listOrder: 5)

        XCTAssertEqual(caree.image, imageData, "Image data should be set correctly")
        XCTAssertEqual(caree.listOrder, 5, "List order should be set correctly")
    }

    // MARK: - CRUD Tests

    func testCreateCaree() throws {
        let caree = Caree(name: "New Caree")
        modelContext.insert(caree)

        try modelContext.save()

        let descriptor = FetchDescriptor<Caree>()
        let carees = try modelContext.fetch(descriptor)

        XCTAssertEqual(carees.count, 1, "Should have one caree")
        XCTAssertEqual(carees.first?.name, "New Caree", "Caree name should match")
    }

    func testUpdateCaree() throws {
        let caree = Caree(name: "Original Name")
        modelContext.insert(caree)
        try modelContext.save()

        caree.name = "Updated Name"
        caree.listOrder = 10
        try modelContext.save()

        let descriptor = FetchDescriptor<Caree>()
        let carees = try modelContext.fetch(descriptor)

        XCTAssertEqual(carees.first?.name, "Updated Name", "Name should be updated")
        XCTAssertEqual(carees.first?.listOrder, 10, "List order should be updated")
    }

    func testDeleteCaree() throws {
        let caree = Caree(name: "To Delete")
        modelContext.insert(caree)
        try modelContext.save()

        modelContext.delete(caree)
        try modelContext.save()

        let descriptor = FetchDescriptor<Caree>()
        let carees = try modelContext.fetch(descriptor)

        XCTAssertTrue(carees.isEmpty, "Caree should be deleted")
    }

    // MARK: - Relationship Tests

    func testCareeActivityTypeRelationship() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree)
        modelContext.insert(activityType)

        try modelContext.save()

        XCTAssertEqual(caree.activityTypes?.count, 1, "Caree should have one activity type")
        XCTAssertEqual(caree.activityTypes?.first?.name, "Feeding", "Activity type should be correct")
    }

    func testCareeCascadeDeleteActivityTypes() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree)
        modelContext.insert(activityType)

        try modelContext.save()

        modelContext.delete(caree)
        try modelContext.save()

        let descriptor = FetchDescriptor<ActivityType>()
        let activityTypes = try modelContext.fetch(descriptor)

        XCTAssertTrue(activityTypes.isEmpty, "Activity types should be cascade deleted")
    }

    func testCareeCascadeDeleteActivities() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let activity = Activity(notes: "Test activity", activityType: activityType, caree: caree)
        modelContext.insert(activity)

        try modelContext.save()

        modelContext.delete(caree)
        try modelContext.save()

        let descriptor = FetchDescriptor<Activity>()
        let activities = try modelContext.fetch(descriptor)

        XCTAssertTrue(activities.isEmpty, "Activities should be cascade deleted")
    }

    // MARK: - Computed Property Tests

    func testSortedActivityTypes() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let type1 = ActivityType(name: "Third", listOrder: 2, caree: caree)
        let type2 = ActivityType(name: "First", listOrder: 0, caree: caree)
        let type3 = ActivityType(name: "Second", listOrder: 1, caree: caree)

        modelContext.insert(type1)
        modelContext.insert(type2)
        modelContext.insert(type3)

        try modelContext.save()

        let sorted = caree.sortedActivityTypes

        XCTAssertEqual(sorted.count, 3, "Should have 3 activity types")
        XCTAssertEqual(sorted[0].name, "First", "First should be at index 0")
        XCTAssertEqual(sorted[1].name, "Second", "Second should be at index 1")
        XCTAssertEqual(sorted[2].name, "Third", "Third should be at index 2")
    }

    func testRecentActivities() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let oldDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let newDate = Date()

        let oldActivity = Activity(dateTime: oldDate, notes: "Old", activityType: activityType, caree: caree)
        let newActivity = Activity(dateTime: newDate, notes: "New", activityType: activityType, caree: caree)

        modelContext.insert(oldActivity)
        modelContext.insert(newActivity)

        try modelContext.save()

        let recent = caree.recentActivities

        XCTAssertEqual(recent.count, 2, "Should have 2 activities")
        XCTAssertEqual(recent[0].notes, "New", "Most recent should be first")
        XCTAssertEqual(recent[1].notes, "Old", "Older should be second")
    }
}
