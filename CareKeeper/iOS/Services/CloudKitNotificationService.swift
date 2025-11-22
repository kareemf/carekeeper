import CloudKit
import SwiftData

/// Service for setting up CloudKit database subscriptions for notifications
/// This enables automatic tracking of accepted shares without manual intervention
@MainActor
class CloudKitNotificationService: ObservableObject {
    private let container = CKContainer(identifier: CloudKitConfig.containerID)
    private let logger = AppLogger.cloudkit

    /// Set up CloudKit database subscriptions for notifications
    /// Note: Uses silent background notifications only - no user permission required
    func setupNotifications(sharedRecordsService: CloudKitSharedRecordsService) async {
        await setupCloudKitSubscriptions()
    }
    
    /// Set up CloudKit database subscriptions to detect share changes
    private func setupCloudKitSubscriptions() async {
        await setupSharedDatabaseSubscription()
        await setupPrivateDatabaseSubscription()
        await setupActivityQuerySubscriptions()
    }
    
    /// Subscribe to changes in the shared database (when shares are accepted)
    private func setupSharedDatabaseSubscription() async {
        let subscriptionID = "shared-database-changes"
        let sharedDatabase = container.sharedCloudDatabase
        
        do {
            // Check if subscription already exists
            let existingSubscriptions = try await sharedDatabase.allSubscriptions()
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
                logger.info("✅ Shared database subscription already exists")
                return
            }

            // Create database subscription for shared database
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
            subscription.notificationInfo = CKSubscription.NotificationInfo()
            subscription.notificationInfo?.shouldSendContentAvailable = true
            subscription.notificationInfo?.shouldBadge = false // Silent notification

            let savedSubscription = try await sharedDatabase.save(subscription)
            logger.info("✅ Created shared database subscription: \(savedSubscription.subscriptionID)")

        } catch {
            logger.error("❌ Error setting up shared database subscription: \(error.localizedDescription)")
        }
    }
    
    /// Subscribe to changes in the private database (when shares are created/modified)
    private func setupPrivateDatabaseSubscription() async {
        let subscriptionID = "private-database-changes"
        let privateDatabase = container.privateCloudDatabase

        do {
            // Check if subscription already exists
            let existingSubscriptions = try await privateDatabase.allSubscriptions()
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
                logger.info("✅ Private database subscription already exists")
                return
            }

            // Create database subscription for private database
            // This catches all changes including share creation/modification
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
            subscription.notificationInfo = CKSubscription.NotificationInfo()
            subscription.notificationInfo?.shouldSendContentAvailable = true
            subscription.notificationInfo?.shouldBadge = false // Silent notification

            let savedSubscription = try await privateDatabase.save(subscription)
            logger.info("✅ Created private database subscription: \(savedSubscription.subscriptionID)")

        } catch {
            logger.error("❌ Error setting up private database subscription: \(error.localizedDescription)")
        }
    }

    /// Subscribe specifically to CD_Activity creations so we can surface user-facing notifications.
    /// Uses query subscriptions on private DB (owners) and shared DB (participants) when supported.
    private func setupActivityQuerySubscriptions() async {
        await setupActivitySubscription(
            scope: .private,
            subscriptionID: "private-activity-created",
            database: container.privateCloudDatabase
        )
    }

    private func setupActivitySubscription(
        scope: CKDatabase.Scope,
        subscriptionID: String,
        database: CKDatabase
    ) async {
        do {
            let existing = try await database.allSubscriptions()
            if existing.contains(where: { $0.subscriptionID == subscriptionID }) {
                logger.info("✅ Activity subscription (\(subscriptionID)) already exists for \(scope.rawValue)")
                return
            }

            let predicate = NSPredicate(value: true)
            let subscription = CKQuerySubscription(
                recordType: "CD_Activity",
                predicate: predicate,
                subscriptionID: subscriptionID,
                options: .firesOnRecordCreation
            )
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            notificationInfo.shouldBadge = false
            subscription.notificationInfo = notificationInfo

            let saved = try await database.save(subscription)
            logger.info("✅ Created activity subscription (\(saved.subscriptionID)) for \(scope.rawValue) database")
        } catch let error as CKError where error.code == .permissionFailure && scope == .shared {
            // Shared DB may reject query subscriptions on older OS versions. Log and proceed.
            logger.warning("⚠️ Shared activity subscription not supported on this OS: \(error.localizedDescription)")
        } catch {
            logger.error("❌ Failed setting up activity subscription (\(subscriptionID)): \(error.localizedDescription)")
        }
    }
}
