@testable import CareKeeper
import XCTest

final class MockReminderMetadataStore: ReminderMetadataStoreProtocol {
    var savedMetadata: [UUID: ActivityReminderMetadata] = [:]
    var deletedActivityIDs: [UUID] = []
    var fetchResults: [UUID: ActivityReminderMetadata] = [:]
    var fetchRequests: [[UUID]] = []

    var saveExpectation: XCTestExpectation?
    var deleteExpectation: XCTestExpectation?
    var fetchExpectation: XCTestExpectation?

    func save(metadata: ActivityReminderMetadata) async throws {
        savedMetadata[metadata.activityID] = metadata
        saveExpectation?.fulfill()
    }

    func deleteMetadata(for activityID: UUID) async {
        deletedActivityIDs.append(activityID)
        deleteExpectation?.fulfill()
    }

    func fetchMetadata(for activityIDs: [UUID]) async throws -> [UUID: ActivityReminderMetadata] {
        fetchRequests.append(activityIDs)
        fetchExpectation?.fulfill()
        return fetchResults.filter { activityIDs.contains($0.key) }
    }
}
