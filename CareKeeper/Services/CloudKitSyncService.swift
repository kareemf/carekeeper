import Foundation
import CloudKit
import SwiftData

@MainActor
class CloudKitSyncService: ObservableObject {
    private let container = CKContainer(identifier: CloudKitConfig.containerID)

    /// Check if a caree has been synced to CloudKit
    func isSynced(caree: Caree) async -> Bool {
        do {
            // SwiftData uses a specific zone for CloudKit sync
            let zoneID = CKRecordZone.ID(zoneName: CloudKitConfig.zoneName)
            let database = container.privateCloudDatabase

            print("🔍 Checking CloudKit for Caree with CD_id: \(caree.id.uuidString)")
            print("   Zone: \(CloudKitConfig.zoneName)")

            // Query by CD_id field instead of record name
            // (CloudKit record name is different from SwiftData model ID)
            let predicate = NSPredicate(format: "CD_id == %@", caree.id.uuidString)
            let query = CKQuery(recordType: "CD_Caree", predicate: predicate)

            let (matchResults, _) = try await database.records(matching: query, inZoneWith: zoneID)

            if let firstMatch = matchResults.first {
                let (_, result) = firstMatch
                switch result {
                case .success(let record):
                    print("✅ Record found in CloudKit!")
                    print("   CloudKit record ID: \(record.recordID.recordName)")
                    print("   CD_id field: \(record["CD_id"] as? String ?? "unknown")")
                    print("   Record type: \(record.recordType)")
                    print("   Fields: \(record.allKeys())")
                    return true
                case .failure(let error):
                    print("❌ Error fetching record: \(error.localizedDescription)")
                    return false
                }
            }

            print("⚠️ Record not found with CD_id: \(caree.id.uuidString)")
            return false
        } catch let error as CKError {
            if error.code == .unknownItem {
                print("⚠️ Record not found in CloudKit (not synced yet)")
                print("   Tried zone: com.apple.coredata.cloudkit.zone")
                print("   Record ID: \(caree.id.uuidString)")
            } else {
                print("❌ CloudKit error: \(error.localizedDescription)")
                print("   Error code: \(error.code.rawValue)")
                print("   Error domain: CKError.errorDomain")
                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] {
                    print("   Underlying error: \(underlyingError)")
                }
            }
            return false
        } catch {
            print("❌ Unexpected error checking sync: \(error.localizedDescription)")
            print("   Error type: \(type(of: error))")
            print("   Full error: \(error)")
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
