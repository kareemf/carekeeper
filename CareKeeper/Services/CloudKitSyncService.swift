import Foundation
import CloudKit
import SwiftData

@MainActor
class CloudKitSyncService: ObservableObject {
    private let container = CKContainer(identifier: CloudKitConfig.containerID)

    /// Check if a caree has been synced to CloudKit
    /// Uses Pure CloudKit approach - checks for record by ID
    func isSynced(caree: Caree) async -> Bool {
        do {
            // Pure CloudKit: Record ID is CD_Caree/{UUID}
            let recordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)")

            print("🔍 Checking CloudKit for Caree record: \(recordID.recordName)")

            // Check if this is a shared caree - they live in shared database
            let isShared = caree.isShared
            let database = isShared ? container.sharedCloudDatabase : container.privateCloudDatabase

            print("   Database: \(isShared ? "Shared" : "Private")")

            // Try to fetch the record directly
            let record = try await database.record(for: recordID)

            print("✅ Record found in CloudKit!")
            print("   CloudKit record ID: \(record.recordID.recordName)")
            print("   Record type: \(record.recordType)")
            print("   Name: \(record["CD_name"] as? String ?? "unknown")")

            return true

        } catch let error as CKError {
            if error.code == .unknownItem {
                print("⚠️ Record not found in CloudKit (not synced yet)")
                print("   Record ID: CD_Caree/\(caree.id.uuidString)")
            } else {
                print("❌ CloudKit error: \(error.localizedDescription)")
                print("   Error code: \(error.code.rawValue)")
                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] {
                    print("   Underlying error: \(underlyingError)")
                }
            }
            return false
        } catch {
            print("❌ Unexpected error checking sync: \(error.localizedDescription)")
            print("   Error type: \(type(of: error))")
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
