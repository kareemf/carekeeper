@testable import CareKeeper
import CoreLocation
import SwiftData
import XCTest

@MainActor
final class ActivityTests: XCTestCase {
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

    func testActivityInitialization() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)
        let activity = Activity(activityType: activityType, caree: caree)

        XCTAssertNotNil(activity.id, "Should have a UUID")
        XCTAssertNotNil(activity.dateTime, "DateTime should be set")
        XCTAssertNil(activity.notes, "Notes should be nil by default")
        XCTAssertNil(activity.quantity, "Quantity should be nil by default")
        XCTAssertNil(activity.latitude, "Latitude should be nil by default")
        XCTAssertNil(activity.longitude, "Longitude should be nil by default")
        XCTAssertNotNil(activity.dateCreated, "dateCreated should be set")
        XCTAssertNotNil(activity.activityType, "activityType relationship should be set")
        XCTAssertNotNil(activity.caree, "caree relationship should be set")
    }

    func testActivityWithAllParameters() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)
        let customDate = Date().addingTimeInterval(-3600)

        let activity = Activity(
            dateTime: customDate,
            notes: "Test note",
            quantity: 5.5,
            latitude: 37.7749,
            longitude: -122.4194,
            activityType: activityType,
            caree: caree
        )

        XCTAssertEqual(activity.dateTime, customDate, "DateTime should be set")
        XCTAssertEqual(activity.notes, "Test note", "Notes should be set")
        XCTAssertEqual(activity.quantity, 5.5, "Quantity should be set")
        XCTAssertEqual(activity.latitude, 37.7749, "Latitude should be set")
        XCTAssertEqual(activity.longitude, -122.4194, "Longitude should be set")
    }

    // MARK: - CRUD Tests

    func testCreateActivity() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let activity = Activity(notes: "Test activity", activityType: activityType, caree: caree)
        modelContext.insert(activity)

        try modelContext.save()

        let descriptor = FetchDescriptor<Activity>()
        let activities = try modelContext.fetch(descriptor)

        XCTAssertEqual(activities.count, 1, "Should have one activity")
        XCTAssertEqual(activities.first?.notes, "Test activity", "Notes should match")
    }

    func testUpdateActivity() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let activity = Activity(notes: "Original", activityType: activityType, caree: caree)
        modelContext.insert(activity)
        try modelContext.save()

        activity.notes = "Updated"
        activity.quantity = 10.0
        activity.latitude = 37.7749
        activity.longitude = -122.4194
        try modelContext.save()

        let descriptor = FetchDescriptor<Activity>()
        let activities = try modelContext.fetch(descriptor)

        XCTAssertEqual(activities.first?.notes, "Updated", "Notes should be updated")
        XCTAssertEqual(activities.first?.quantity, 10.0, "Quantity should be updated")
        XCTAssertEqual(activities.first?.latitude, 37.7749, "Latitude should be updated")
        XCTAssertEqual(activities.first?.longitude, -122.4194, "Longitude should be updated")
    }

    func testDeleteActivity() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let activity = Activity(activityType: activityType, caree: caree)
        modelContext.insert(activity)
        try modelContext.save()

        modelContext.delete(activity)
        try modelContext.save()

        let descriptor = FetchDescriptor<Activity>()
        let activities = try modelContext.fetch(descriptor)

        XCTAssertTrue(activities.isEmpty, "Activity should be deleted")
    }

    // MARK: - Relationship Tests

    func testActivityRelationships() throws {
        let caree = Caree(name: "Test Caree")
        modelContext.insert(caree)

        let activityType = ActivityType(name: "Feeding", caree: caree)
        modelContext.insert(activityType)

        let activity = Activity(activityType: activityType, caree: caree)
        modelContext.insert(activity)

        try modelContext.save()

        XCTAssertEqual(activity.activityType?.name, "Feeding", "Should be linked to activity type")
        XCTAssertEqual(activity.caree?.name, "Test Caree", "Should be linked to caree")
        XCTAssertTrue(
            activityType.activities?.contains(where: { $0.id == activity.id }) ?? false,
            "Activity type should have activity"
        )
        XCTAssertTrue(caree.activities?.contains(where: { $0.id == activity.id }) ?? false, "Caree should have activity")
    }

    // MARK: - Location Tests

    func testHasLocationTrue() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Walk", hasLocation: true, caree: caree)
        let activity = Activity(
            latitude: 37.7749,
            longitude: -122.4194,
            activityType: activityType,
            caree: caree
        )

        XCTAssertTrue(activity.hasLocation, "Should have location when both coordinates are set")
    }

    func testHasLocationFalse() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)
        let activity = Activity(activityType: activityType, caree: caree)

        XCTAssertFalse(activity.hasLocation, "Should not have location when coordinates are nil")
    }

    func testHasLocationWithOnlyLatitude() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Walk", caree: caree)
        let activity = Activity(latitude: 37.7749, activityType: activityType, caree: caree)

        XCTAssertFalse(activity.hasLocation, "Should not have location with only latitude")
    }

    func testHasLocationWithOnlyLongitude() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Walk", caree: caree)
        let activity = Activity(longitude: -122.4194, activityType: activityType, caree: caree)

        XCTAssertFalse(activity.hasLocation, "Should not have location with only longitude")
    }

    func testLocationProperty() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Walk", caree: caree)
        let activity = Activity(
            latitude: 37.7749,
            longitude: -122.4194,
            activityType: activityType,
            caree: caree
        )

        let location = activity.location

        XCTAssertNotNil(location, "Location should not be nil")
        if let location {
            XCTAssertEqual(location.coordinate.latitude, 37.7749, accuracy: 0.0001, "Latitude should match")
            XCTAssertEqual(location.coordinate.longitude, -122.4194, accuracy: 0.0001, "Longitude should match")
        }
    }

    func testLocationPropertyNil() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)
        let activity = Activity(activityType: activityType, caree: caree)

        XCTAssertNil(activity.location, "Location should be nil when coordinates are not set")
    }

    // MARK: - Formatted Property Tests

    func testFormattedDateTime() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)
        let activity = Activity(activityType: activityType, caree: caree)

        let formatted = activity.formattedDateTime

        XCTAssertFalse(formatted.isEmpty, "Formatted date time should not be empty")
        XCTAssertTrue(formatted.contains(","), "Should contain date-time separator")
    }

    func testFormattedQuantityWithValue() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", hasQuantity: true, quantityUnit: "oz", caree: caree)
        let activity = Activity(quantity: 5.5, activityType: activityType, caree: caree)

        let formatted = activity.formattedQuantity

        XCTAssertEqual(formatted, "5.5 oz", "Should format quantity with unit")
    }

    func testFormattedQuantityWithoutUnit() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Walk", hasQuantity: true, caree: caree)
        let activity = Activity(quantity: 10.0, activityType: activityType, caree: caree)

        let formatted = activity.formattedQuantity

        XCTAssertEqual(formatted, "10.0", "Should format quantity without unit")
    }

    func testFormattedQuantityNil() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", caree: caree)
        let activity = Activity(activityType: activityType, caree: caree)

        XCTAssertNil(activity.formattedQuantity, "Formatted quantity should be nil when quantity is not set")
    }

    // MARK: - Business Logic Tests

    func testQuantityZeroIsValid() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", hasQuantity: true, caree: caree)
        let activity = Activity(quantity: 0.0, activityType: activityType, caree: caree)

        XCTAssertEqual(activity.quantity, 0.0, "Zero should be a valid quantity")
        XCTAssertNotNil(activity.formattedQuantity, "Should format zero quantity")
    }

    func testNegativeQuantity() {
        let caree = Caree(name: "Test Caree")
        let activityType = ActivityType(name: "Feeding", hasQuantity: true, caree: caree)
        let activity = Activity(quantity: -5.0, activityType: activityType, caree: caree)

        // Note: Current implementation doesn't validate negative quantities
        // This test documents the current behavior
        XCTAssertEqual(activity.quantity, -5.0, "Negative quantities are currently allowed")
    }
}
