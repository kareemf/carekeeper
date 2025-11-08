@testable import CareKeeper
import XCTest

final class SnapshotCodableTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testCareeSnapshotRoundTrip() throws {
        let snapshot = CareeSnapshot(
            id: UUID(),
            name: "Jamie",
            imageData: Data("avatar".utf8),
            isShared: true,
            changeTag: "abcd",
            listOrder: 2,
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            activityTypeCount: 4
        )

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(CareeSnapshot.self, from: data)

        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.name, snapshot.name)
        XCTAssertEqual(decoded.imageData, snapshot.imageData)
        XCTAssertEqual(decoded.changeTag, snapshot.changeTag)
        XCTAssertEqual(decoded.isShared, snapshot.isShared)
        XCTAssertEqual(decoded.listOrder, snapshot.listOrder)
        XCTAssertEqual(decoded.activityTypeCount, snapshot.activityTypeCount)
        XCTAssertEqual(decoded.dateCreated.timeIntervalSince1970, snapshot.dateCreated.timeIntervalSince1970, accuracy: 0.1)
    }

    func testActivityTypeSnapshotRoundTrip() throws {
        let snapshot = ActivityTypeSnapshot(
            id: UUID(),
            name: "Feeding",
            icon: "🍼",
            hasQuantity: true,
            quantityUnit: "oz",
            hasLocation: false,
            listOrder: 1,
            careeID: UUID(),
            dateCreated: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(ActivityTypeSnapshot.self, from: data)

        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.name, snapshot.name)
        XCTAssertEqual(decoded.icon, snapshot.icon)
        XCTAssertEqual(decoded.hasQuantity, snapshot.hasQuantity)
        XCTAssertEqual(decoded.quantityUnit, snapshot.quantityUnit)
        XCTAssertEqual(decoded.hasLocation, snapshot.hasLocation)
        XCTAssertEqual(decoded.listOrder, snapshot.listOrder)
        XCTAssertEqual(decoded.careeID, snapshot.careeID)
    }

    func testActivitySnapshotRoundTripWithFailedState() throws {
        var snapshot = ActivitySnapshot(
            id: UUID(),
            dateTime: Date(timeIntervalSince1970: 1_700_200_000),
            notes: "Night feed",
            quantity: 4.5,
            latitude: 37.334_900,
            longitude: -122.009_020,
            activityTypeID: UUID(),
            careeID: UUID(),
            dateCreated: Date(timeIntervalSince1970: 1_700_100_000),
            syncState: .synced
        )
        snapshot.syncState = .failed("Network timeout")

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(ActivitySnapshot.self, from: data)

        XCTAssertEqual(decoded.id, snapshot.id)
        XCTAssertEqual(decoded.dateTime.timeIntervalSince1970, snapshot.dateTime.timeIntervalSince1970, accuracy: 0.1)
        XCTAssertEqual(decoded.notes, snapshot.notes)
        XCTAssertEqual(decoded.quantity, snapshot.quantity)
        XCTAssertEqual(decoded.latitude, snapshot.latitude)
        XCTAssertEqual(decoded.longitude, snapshot.longitude)
        XCTAssertEqual(decoded.activityTypeID, snapshot.activityTypeID)
        XCTAssertEqual(decoded.careeID, snapshot.careeID)

        if case let .failed(message) = decoded.syncState {
            XCTAssertEqual(message, "Network timeout")
        } else {
            XCTFail("Expected failed sync state")
        }
    }

    func testActivitySnapshotSyncStates() throws {
        let states: [ActivitySnapshot.SyncState] = [
            .pending,
            .syncing,
            .synced,
            .failed("Server error"),
        ]

        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(ActivitySnapshot.SyncState.self, from: data)

            switch (state, decoded) {
            case (.pending, .pending),
                 (.syncing, .syncing),
                 (.synced, .synced):
                continue
            case let (.failed(message), .failed(decodedMessage)):
                XCTAssertEqual(decodedMessage, message)
            default:
                XCTFail("Unexpected state mapping: \(state) -> \(decoded)")
            }
        }
    }

    func testActivitySnapshotEqualityDetectsFieldUpdates() {
        let careeID = UUID()
        let typeID = UUID()
        let createdDate = Date(timeIntervalSince1970: 1_700_300_000)
        let base = ActivitySnapshot(
            id: UUID(),
            dateTime: Date(timeIntervalSince1970: 1_700_400_000),
            notes: "Original",
            quantity: 1.0,
            latitude: 37.0,
            longitude: -122.0,
            activityTypeID: typeID,
            careeID: careeID,
            dateCreated: createdDate,
            syncState: .synced
        )

        let updated = ActivitySnapshot(
            id: base.id,
            dateTime: base.dateTime.addingTimeInterval(60),
            notes: "Updated",
            quantity: 2.0,
            latitude: base.latitude,
            longitude: base.longitude,
            activityTypeID: typeID,
            careeID: careeID,
            dateCreated: createdDate,
            syncState: .syncing
        )

        XCTAssertNotEqual(base, updated)
    }
}
