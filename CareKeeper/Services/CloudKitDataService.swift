import Foundation
import CloudKit
import SwiftUI

/// Single source of truth for all CloudKit data operations
/// Replaces direct SwiftData+CloudKit sync with explicit CRUD operations
@MainActor
class CloudKitDataService: ObservableObject {

    // MARK: - Published Properties

    @Published var isSyncing = false
    @Published var lastSyncError: Error?
    @Published var syncStatus: SyncStatus = .idle

    // MARK: - Private Properties

    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let converter = CloudKitRecordConverter()
    private let logger = AppLogger.cloudkit
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 2.0

    // MARK: - Sync Status

    enum SyncStatus {
        case idle
        case syncing
        case synced
        case failed(Error)

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    // MARK: - Database Selection

    /// Get the appropriate database for a record based on whether it's shared
    private func database(for isShared: Bool) -> CKDatabase {
        return isShared ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    // MARK: - Caree Operations

    /// Create a new Caree in CloudKit
    /// - Parameters:
    ///   - name: Caree name
    ///   - imageData: Optional profile image
    ///   - listOrder: Display order
    /// - Returns: Created Caree with CloudKit sync confirmed
    func createCaree(name: String, imageData: Data?, listOrder: Int) async throws -> Caree {
        logger.info("Creating Caree: \(name)")
        syncStatus = .syncing

        do {
            // Create domain model
            let caree = Caree(name: name, listOrder: listOrder)
            caree.image = imageData

            // Convert to CKRecord
            let record = try await converter.careeToRecord(caree, imageData: imageData)

            // Save to CloudKit private database
            let savedRecord = try await saveWithRetry(record, to: container.privateCloudDatabase)

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: container.privateCloudDatabase)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model with any CloudKit modifications
            let syncedCaree = try await converter.recordToCaree(savedRecord)

            logger.info("✅ Caree created and verified: \(syncedCaree.id)")
            syncStatus = .synced
            return syncedCaree

        } catch {
            logger.error("❌ Failed to create Caree: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Update an existing Caree in CloudKit
    /// - Parameters:
    ///   - caree: Caree to update
    ///   - name: New name (optional)
    ///   - imageData: New image data (optional)
    ///   - isShared: Whether this is a shared caree
    func updateCaree(_ caree: Caree, name: String? = nil, imageData: Data? = nil, isShared: Bool = false) async throws {
        logger.info("Updating Caree: \(caree.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)")
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let name = name {
                existingRecord["CD_name"] = name as CKRecordValue
            }

            if let imageData = imageData {
                let asset = try converter.createImageAsset(from: imageData)
                existingRecord["CD_image"] = asset
            }

            // Save updated record
            let savedRecord = try await saveWithRetry(existingRecord, to: db)

            logger.info("✅ Caree updated: \(caree.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to update Caree: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Delete a Caree from CloudKit (cascades to children via parent references)
    /// - Parameters:
    ///   - caree: Caree to delete
    ///   - isShared: Whether this is a shared caree
    func deleteCaree(_ caree: Caree, isShared: Bool = false) async throws {
        logger.info("Deleting Caree: \(caree.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)")

            // Delete from CloudKit (child records cascade via .deleteSelf action)
            try await deleteWithRetry(recordID: recordID, from: db)

            logger.info("✅ Caree deleted: \(caree.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete Caree: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Fetch a specific Caree from CloudKit
    /// - Parameters:
    ///   - id: Caree UUID
    ///   - isShared: Whether to query shared database
    /// - Returns: Caree if found
    func fetchCaree(id: UUID, isShared: Bool = false) async throws -> Caree? {
        logger.info("Fetching Caree: \(id)")

        let db = database(for: isShared)
        let recordID = CKRecord.ID(recordName: "CD_Caree/\(id.uuidString)")

        do {
            let record = try await fetchWithRetry(recordID: recordID, from: db)
            let caree = try await converter.recordToCaree(record)
            logger.info("✅ Caree fetched: \(id)")
            return caree
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("Caree not found: \(id)")
            return nil
        } catch {
            logger.error("❌ Failed to fetch Caree: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch all Carees from private database
    /// - Returns: Array of Carees
    func fetchAllCarees() async throws -> [Caree] {
        logger.info("Fetching all Carees from private database")

        let query = CKQuery(recordType: "CD_Caree", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "CD_listOrder", ascending: true)]

        let (matchResults, _) = try await container.privateCloudDatabase.records(matching: query)

        var carees: [Caree] = []
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                do {
                    let caree = try await converter.recordToCaree(record)
                    carees.append(caree)
                } catch {
                    logger.warning("Failed to convert Caree record: \(error.localizedDescription)")
                }
            case .failure(let error):
                logger.warning("Failed to fetch Caree record: \(error.localizedDescription)")
            }
        }

        logger.info("✅ Fetched \(carees.count) Carees")
        return carees
    }

    // MARK: - ActivityType Operations

    /// Create a new ActivityType for a Caree
    /// - Parameters:
    ///   - caree: Parent Caree
    ///   - name: ActivityType name
    ///   - icon: Optional icon string
    ///   - hasQuantity: Whether quantity tracking is enabled
    ///   - quantityUnit: Optional quantity unit
    ///   - hasLocation: Whether location tracking is enabled
    ///   - listOrder: Display order
    ///   - isShared: Whether parent caree is shared
    /// - Returns: Created ActivityType
    func createActivityType(
        for caree: Caree,
        name: String,
        icon: String?,
        hasQuantity: Bool,
        quantityUnit: String?,
        hasLocation: Bool,
        listOrder: Int,
        isShared: Bool = false
    ) async throws -> ActivityType {
        logger.info("Creating ActivityType: \(name) for Caree: \(caree.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)

            // Fetch parent Caree record (needed for parent reference)
            let parentRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)")
            let parentRecord = try await fetchWithRetry(recordID: parentRecordID, from: db)

            // Create domain model
            let activityType = ActivityType(
                name: name,
                icon: icon,
                hasQuantity: hasQuantity,
                quantityUnit: quantityUnit,
                hasLocation: hasLocation,
                listOrder: listOrder
            )

            // Convert to CKRecord with parent reference
            let record = try converter.activityTypeToRecord(activityType, parentCaree: parentRecord)

            // Save to CloudKit
            let savedRecord = try await saveWithRetry(record, to: db)

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: db)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model
            let syncedActivityType = try converter.recordToActivityType(savedRecord)

            logger.info("✅ ActivityType created and verified: \(syncedActivityType.id)")
            syncStatus = .synced
            return syncedActivityType

        } catch {
            logger.error("❌ Failed to create ActivityType: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Update an existing ActivityType
    /// - Parameters:
    ///   - activityType: ActivityType to update
    ///   - caree: Parent Caree (for parent reference)
    ///   - name: New name (optional)
    ///   - icon: New icon (optional)
    ///   - isShared: Whether parent caree is shared
    func updateActivityType(
        _ activityType: ActivityType,
        caree: Caree,
        name: String? = nil,
        icon: String? = nil,
        isShared: Bool = false
    ) async throws {
        logger.info("Updating ActivityType: \(activityType.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)")
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let name = name {
                existingRecord["CD_name"] = name as CKRecordValue
            }
            if let icon = icon {
                existingRecord["CD_icon"] = icon as CKRecordValue
            }

            // Save updated record
            _ = try await saveWithRetry(existingRecord, to: db)

            logger.info("✅ ActivityType updated: \(activityType.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to update ActivityType: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Delete an ActivityType from CloudKit
    /// - Parameters:
    ///   - activityType: ActivityType to delete
    ///   - isShared: Whether parent caree is shared
    func deleteActivityType(_ activityType: ActivityType, isShared: Bool = false) async throws {
        logger.info("Deleting ActivityType: \(activityType.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)")

            try await deleteWithRetry(recordID: recordID, from: db)

            logger.info("✅ ActivityType deleted: \(activityType.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete ActivityType: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    // MARK: - Activity Operations

    /// Create a new Activity
    /// - Parameters:
    ///   - caree: Parent Caree
    ///   - activityType: Associated ActivityType
    ///   - dateTime: When the activity occurred
    ///   - notes: Optional notes
    ///   - quantity: Optional quantity value
    ///   - latitude: Optional latitude
    ///   - longitude: Optional longitude
    ///   - isShared: Whether parent caree is shared
    /// - Returns: Created Activity
    func createActivity(
        for caree: Caree,
        activityType: ActivityType,
        dateTime: Date,
        notes: String?,
        quantity: Double?,
        latitude: Double?,
        longitude: Double?,
        isShared: Bool = false
    ) async throws -> Activity {
        logger.info("Creating Activity for Caree: \(caree.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)

            // Fetch parent records
            let careeRecordID = CKRecord.ID(recordName: "CD_Caree/\(caree.id.uuidString)")
            let careeRecord = try await fetchWithRetry(recordID: careeRecordID, from: db)

            let activityTypeRecordID = CKRecord.ID(recordName: "CD_ActivityType/\(activityType.id.uuidString)")
            let activityTypeRecord = try await fetchWithRetry(recordID: activityTypeRecordID, from: db)

            // Create domain model
            let activity = Activity(
                dateTime: dateTime,
                notes: notes,
                quantity: quantity,
                latitude: latitude,
                longitude: longitude
            )

            // Convert to CKRecord with parent references
            let record = try converter.activityToRecord(
                activity,
                parentCaree: careeRecord,
                activityTypeRecord: activityTypeRecord
            )

            // Save to CloudKit
            let savedRecord = try await saveWithRetry(record, to: db)

            // Verify sync
            let verified = try await verifySynced(recordID: savedRecord.recordID, in: db)
            guard verified else {
                throw DataServiceError.syncVerificationFailed(recordID: savedRecord.recordID.recordName)
            }

            // Convert back to domain model
            let syncedActivity = try converter.recordToActivity(savedRecord)

            logger.info("✅ Activity created and verified: \(syncedActivity.id)")
            syncStatus = .synced
            return syncedActivity

        } catch {
            logger.error("❌ Failed to create Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Update an existing Activity
    /// - Parameters:
    ///   - activity: Activity to update
    ///   - caree: Parent Caree
    ///   - activityType: Associated ActivityType
    ///   - dateTime: New dateTime (optional)
    ///   - notes: New notes (optional)
    ///   - quantity: New quantity (optional)
    ///   - isShared: Whether parent caree is shared
    func updateActivity(
        _ activity: Activity,
        caree: Caree,
        activityType: ActivityType,
        dateTime: Date? = nil,
        notes: String? = nil,
        quantity: Double? = nil,
        isShared: Bool = false
    ) async throws {
        logger.info("Updating Activity: \(activity.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)

            // Fetch existing record
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)")
            let existingRecord = try await fetchWithRetry(recordID: recordID, from: db)

            // Update fields
            if let dateTime = dateTime {
                existingRecord["CD_dateTime"] = dateTime as CKRecordValue
            }
            if let notes = notes {
                existingRecord["CD_notes"] = notes as CKRecordValue
            }
            if let quantity = quantity {
                existingRecord["CD_quantity"] = quantity as CKRecordValue
            }

            // Save updated record
            _ = try await saveWithRetry(existingRecord, to: db)

            logger.info("✅ Activity updated: \(activity.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to update Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    /// Delete an Activity from CloudKit
    /// - Parameters:
    ///   - activity: Activity to delete
    ///   - isShared: Whether parent caree is shared
    func deleteActivity(_ activity: Activity, isShared: Bool = false) async throws {
        logger.info("Deleting Activity: \(activity.id)")
        syncStatus = .syncing

        do {
            let db = database(for: isShared)
            let recordID = CKRecord.ID(recordName: "CD_Activity/\(activity.id.uuidString)")

            try await deleteWithRetry(recordID: recordID, from: db)

            logger.info("✅ Activity deleted: \(activity.id)")
            syncStatus = .synced

        } catch {
            logger.error("❌ Failed to delete Activity: \(error.localizedDescription)")
            syncStatus = .failed(error)
            throw error
        }
    }

    // MARK: - Sync Verification

    /// Verify that a record exists in CloudKit
    /// - Parameters:
    ///   - recordID: CKRecord.ID to verify
    ///   - database: Database to query
    /// - Returns: true if record exists
    func verifySynced(recordID: CKRecord.ID, in database: CKDatabase) async throws -> Bool {
        do {
            _ = try await database.record(for: recordID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw error
        }
    }

    /// Wait for a record to sync to CloudKit with timeout
    /// - Parameters:
    ///   - recordID: CKRecord.ID to wait for
    ///   - database: Database to query
    ///   - timeout: Maximum wait time in seconds
    ///   - pollInterval: How often to check (default 0.5s)
    /// - Returns: true if record found before timeout
    func waitForSync(
        recordID: CKRecord.ID,
        in database: CKDatabase,
        timeout: TimeInterval = 10.0,
        pollInterval: TimeInterval = 0.5
    ) async throws -> Bool {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if try await verifySynced(recordID: recordID, in: database) {
                logger.info("✅ Record synced: \(recordID.recordName)")
                return true
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        logger.warning("⏱️ Sync verification timeout for: \(recordID.recordName)")
        return false
    }

    // MARK: - Retry Logic

    /// Save a record with automatic retry on network failures
    private func saveWithRetry(_ record: CKRecord, to database: CKDatabase) async throws -> CKRecord {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                let savedRecord = try await database.save(record)
                if attempt > 0 {
                    logger.info("✅ Save succeeded after \(attempt) retries")
                }
                return savedRecord
            } catch let error as CKError where error.isRetryable {
                lastError = error
                attempt += 1
                logger.warning("⚠️ Save failed (attempt \(attempt)/\(maxRetries)), retrying: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            } catch {
                // Non-retryable error, throw immediately
                throw error
            }
        }

        // Max retries exceeded
        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    /// Fetch a record with automatic retry on network failures
    private func fetchWithRetry(recordID: CKRecord.ID, from database: CKDatabase) async throws -> CKRecord {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                let record = try await database.record(for: recordID)
                if attempt > 0 {
                    logger.info("✅ Fetch succeeded after \(attempt) retries")
                }
                return record
            } catch let error as CKError where error.isRetryable {
                lastError = error
                attempt += 1
                logger.warning("⚠️ Fetch failed (attempt \(attempt)/\(maxRetries)), retrying: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            } catch {
                // Non-retryable error, throw immediately
                throw error
            }
        }

        // Max retries exceeded
        throw lastError ?? DataServiceError.maxRetriesExceeded
    }

    /// Delete a record with automatic retry on network failures
    private func deleteWithRetry(recordID: CKRecord.ID, from database: CKDatabase) async throws {
        var attempt = 0
        var lastError: Error?

        while attempt < maxRetries {
            do {
                _ = try await database.deleteRecord(withID: recordID)
                if attempt > 0 {
                    logger.info("✅ Delete succeeded after \(attempt) retries")
                }
                return
            } catch let error as CKError where error.isRetryable {
                lastError = error
                attempt += 1
                logger.warning("⚠️ Delete failed (attempt \(attempt)/\(maxRetries)), retrying: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(retryDelay * Double(attempt) * 1_000_000_000))
            } catch {
                // Non-retryable error, throw immediately
                throw error
            }
        }

        // Max retries exceeded
        throw lastError ?? DataServiceError.maxRetriesExceeded
    }
}

// MARK: - CKError Extension

extension CKError {
    /// Determine if error is retryable
    var isRetryable: Bool {
        switch code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }
}

// MARK: - Data Service Errors

enum DataServiceError: LocalizedError {
    case syncVerificationFailed(recordID: String)
    case maxRetriesExceeded
    case parentRecordNotFound(careeID: UUID)

    var errorDescription: String? {
        switch self {
        case .syncVerificationFailed(let recordID):
            return "Failed to verify sync for record: \(recordID)"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded. Please check your network connection."
        case .parentRecordNotFound(let careeID):
            return "Parent caree record not found: \(careeID)"
        }
    }
}
