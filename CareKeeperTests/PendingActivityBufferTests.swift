@testable import CareKeeper
import XCTest

@MainActor
final class PendingActivityBufferTests: XCTestCase {
    var buffer: PendingActivityBuffer!

    override func setUp() {
        buffer = PendingActivityBuffer()
    }

    override func tearDown() {
        buffer = nil
    }

    // MARK: - Helpers

    private func makeMutation(
        activityID: UUID = UUID(),
        careeID: UUID = UUID(),
        activityTypeID: UUID = UUID()
    ) -> PendingActivityBuffer.PendingActivityMutation {
        let activity = CareKeeper.Activity(
            dateTime: Date(),
            notes: "test",
            activityType: nil,
            caree: nil
        )
        activity.id = activityID
        return PendingActivityBuffer.PendingActivityMutation(
            id: activityID,
            careeID: careeID,
            activityTypeID: activityTypeID,
            activity: activity,
            createdAt: Date()
        )
    }

    // MARK: - Enqueue / Remove

    func testEnqueueAddsMutation() {
        let careeID = UUID()
        let mutation = makeMutation(careeID: careeID)

        buffer.enqueue(mutation)

        XCTAssertEqual(buffer.pendingMutations(for: careeID).count, 1)
        XCTAssertEqual(buffer.pendingActivities(for: careeID).count, 1)
    }

    func testRemoveByActivityID() {
        let careeID = UUID()
        let activityID = UUID()
        let mutation = makeMutation(activityID: activityID, careeID: careeID)

        buffer.enqueue(mutation)
        XCTAssertEqual(buffer.pendingMutations(for: careeID).count, 1)

        buffer.remove(activityID: activityID, careeID: careeID)
        XCTAssertTrue(buffer.pendingMutations(for: careeID).isEmpty)
    }

    func testRemoveOnlyTargetsSpecifiedActivity() {
        let careeID = UUID()
        let keep = makeMutation(careeID: careeID)
        let remove = makeMutation(careeID: careeID)

        buffer.enqueue(keep)
        buffer.enqueue(remove)
        XCTAssertEqual(buffer.pendingMutations(for: careeID).count, 2)

        buffer.remove(activityID: remove.id, careeID: careeID)
        XCTAssertEqual(buffer.pendingMutations(for: careeID).count, 1)
        XCTAssertEqual(buffer.pendingMutations(for: careeID).first?.id, keep.id)
    }

    func testRemoveWithWrongCareeIDIsNoOp() {
        let careeID = UUID()
        let otherCareeID = UUID()
        let mutation = makeMutation(careeID: careeID)

        buffer.enqueue(mutation)
        buffer.remove(activityID: mutation.id, careeID: otherCareeID)

        XCTAssertEqual(buffer.pendingMutations(for: careeID).count, 1, "Should not remove from wrong caree")
    }

    // MARK: - Drain

    func testDrainReturnsAndClears() {
        let careeID = UUID()
        buffer.enqueue(makeMutation(careeID: careeID))
        buffer.enqueue(makeMutation(careeID: careeID))

        let drained = buffer.drain(for: careeID)
        XCTAssertEqual(drained.count, 2)
        XCTAssertTrue(buffer.pendingMutations(for: careeID).isEmpty)
    }

    // MARK: - Caree Isolation

    func testPendingCareeIDsReflectsAllCarees() {
        let caree1 = UUID()
        let caree2 = UUID()

        buffer.enqueue(makeMutation(careeID: caree1))
        buffer.enqueue(makeMutation(careeID: caree2))

        let ids = Set(buffer.pendingCareeIDs)
        XCTAssertEqual(ids, [caree1, caree2])
    }

    func testMutationsIsolatedByCaree() {
        let caree1 = UUID()
        let caree2 = UUID()

        buffer.enqueue(makeMutation(careeID: caree1))
        buffer.enqueue(makeMutation(careeID: caree1))
        buffer.enqueue(makeMutation(careeID: caree2))

        XCTAssertEqual(buffer.pendingMutations(for: caree1).count, 2)
        XCTAssertEqual(buffer.pendingMutations(for: caree2).count, 1)
    }

    // MARK: - Empty State

    func testEmptyBufferReturnsNoMutations() {
        XCTAssertTrue(buffer.pendingMutations(for: UUID()).isEmpty)
        XCTAssertTrue(buffer.pendingActivities(for: UUID()).isEmpty)
        XCTAssertTrue(buffer.pendingCareeIDs.isEmpty)
    }

    func testRemoveLastEntryCleansCareeDictionary() {
        let careeID = UUID()
        let mutation = makeMutation(careeID: careeID)

        buffer.enqueue(mutation)
        buffer.remove(activityID: mutation.id, careeID: careeID)

        // After removing the only entry, the caree should be cleaned up
        XCTAssertTrue(buffer.pendingCareeIDs.isEmpty)
    }
}
