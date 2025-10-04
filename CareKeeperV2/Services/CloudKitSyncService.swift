import Foundation
import CloudKit
import SwiftData

@MainActor
class CloudKitSyncService: ObservableObject {
    private let container = CKContainer(identifier: "iCloud.com.kareemf.CareKeeperCloudKit")

    /// Check if a caree has been synced to CloudKit
    func isSynced(caree: Caree) async -> Bool {
        do {
            let recordID = CKRecord.ID(recordName: caree.id.uuidString)
            let database = container.privateCloudDatabase

            // Try to fetch the record
            _ = try await database.record(for: recordID)
            return true
        } catch {
            // Record not found or other error means not synced
            return false
        }
    }

    /// Check CloudKit account availability
    func checkAccountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }
}
