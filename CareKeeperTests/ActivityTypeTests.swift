@testable import CareKeeperV2
import SwiftData
import XCTest

@MainActor
final class ActivityTypeTests: XCTestCase {
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

    func testActivityTypeInitialization() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)

        XCTAssertNotNil(activityType.id, "Should have a UUID")
        XCTAssertEqual(activityType.name, "Feeding", "Name should be set correctly")
        XCTAssertNil(activityType.icon, "Icon should be nil by default")
        XCTAssertFalse(activityType.hasQuantity, "hasQuantity should be false by default")
        XCTAssertNil(activityType.quantityUnit, "quantityUnit should be nil by default")
        XCTAssertFalse(activityType.hasLocation, "hasLocation should be false by default")
        XCTAssertEqual(activityType.listOrder, 0, "listOrder should default to 0")
        XCTAssertNotNil(activityType.dateCreated, "dateCreated should be set")
        XCTAssertNotNil(activityType.caree, "caree relationship should be set")
    }

    func testActivityTypeWithAllParameters() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(
            name: "Bottle Feeding",
            icon: "🍼",
            hasQuantity: true,
            quantityUnit: "oz",
            hasLocation: true,
            listOrder: 5,
            caree: caree
        )

        XCTAssertEqual(activityType.icon, "🍼", "Icon should be set")
        XCTAssertTrue(activityType.hasQuantity, "hasQuantity should be true")
        XCTAssertEqual(activityType.quantityUnit, "oz", "quantityUnit should be set")
        XCTAssertTrue(activityType.hasLocation, "hasLocation should be true")
        XCTAssertEqual(activityType.listOrder, 5, "listOrder should be set")
    }

    // MARK: - CRUD Tests

    func testCreateActivityType() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree)
        modelContext.insert(activityType)

        try modelContext.save()

        let descriptor = FetchDescriptor<ActivityType>()
        let activityTypes = try modelContext.fetch(descriptor)

        XCTAssertEqual(activityTypes.count, 1, "Should have one activity type")
        XCTAssertEqual(activityTypes.first?.name, "Feeding", "Name should match")
    }

    func testUpdateActivityType() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Original", caree: caree)
        modelContext.insert(activityType)
        try modelContext.save()

        activityType.name = "Updated"
        activityType.icon = "✅"
        activityType.hasQuantity = true
        activityType.quantityUnit = "ml"
        try modelContext.save()

        let descriptor = FetchDescriptor<ActivityType>()
        let activityTypes = try modelContext.fetch(descriptor)

        XCTAssertEqual(activityTypes.first?.name, "Updated", "Name should be updated")
        XCTAssertEqual(activityTypes.first?.icon, "✅", "Icon should be updated")
        XCTAssertTrue(activityTypes.first?.hasQuantity ?? false, "hasQuantity should be updated")
        XCTAssertEqual(activityTypes.first?.quantityUnit, "ml", "quantityUnit should be updated")
    }

    func testDeleteActivityType() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "To Delete", caree: caree)
        modelContext.insert(activityType)
        try modelContext.save()

        modelContext.delete(activityType)
        try modelContext.save()

        let descriptor = FetchDescriptor<ActivityType>()
        let activityTypes = try modelContext.fetch(descriptor)

        XCTAssertTrue(activityTypes.isEmpty, "Activity type should be deleted")
    }

    // MARK: - Relationship Tests

    func testActivityTypeCareeRelationship() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        try modelContext.save()

        XCTAssertEqual(activityType.caree?.name, "Test Caree", "Should be linked to caree")
        XCTAssertTrue(
            caree.activityTypes?.contains(where: { $0.id == activityType.id }) ?? false,
            "Caree should have activity type"
        )
    }

    func testActivityTypeCascadeDeleteActivities() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let activity = Activity(notes: "Test", activityType: activityType, caree: caree)
        modelContext.insert(activity)

        try modelContext.save()

        modelContext.delete(activityType)
        try modelContext.save()

        let descriptor = FetchDescriptor<Activity>()
        let activities = try modelContext.fetch(descriptor)

        XCTAssertTrue(activities.isEmpty, "Activities should be cascade deleted")
    }

    // MARK: - Computed Property Tests

    func testDisplayIconWithIcon() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", icon: "🍼", caree: caree)

        XCTAssertEqual(activityType.displayIcon, "🍼", "Should return the icon")
    }

    func testDisplayIconWithoutIcon() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)

        XCTAssertEqual(activityType.displayIcon, "", "Should return empty string when no icon")
    }

    func testDisplayIconWithEmptyString() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", icon: "", caree: caree)

        XCTAssertEqual(activityType.displayIcon, "", "Should return empty string for empty icon")
    }

    func testRecentActivities() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let oldDate = Date().addingTimeInterval(-7200) // 2 hours ago
        let newDate = Date()

        let oldActivity = Activity(dateTime: oldDate, notes: "Old", activityType: activityType, caree: caree)
        let newActivity = Activity(dateTime: newDate, notes: "New", activityType: activityType, caree: caree)

        modelContext.insert(oldActivity)
        modelContext.insert(newActivity)

        try modelContext.save()

        let recent = activityType.recentActivities

        XCTAssertEqual(recent.count, 2, "Should have 2 activities")
        XCTAssertEqual(recent[0].notes, "New", "Most recent should be first")
        XCTAssertEqual(recent[1].notes, "Old", "Older should be second")
    }

    func testTotalActivitiesCount() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        XCTAssertEqual(activityType.totalActivitiesCount, 0, "Should start with 0 activities")

        let activity1 = Activity(activityType: activityType, caree: caree)
        let activity2 = Activity(activityType: activityType, caree: caree)
        let activity3 = Activity(activityType: activityType, caree: caree)

        modelContext.insert(activity1)
        modelContext.insert(activity2)
        modelContext.insert(activity3)

        try modelContext.save()

        XCTAssertEqual(activityType.totalActivitiesCount, 3, "Should have 3 activities")
    }
}
