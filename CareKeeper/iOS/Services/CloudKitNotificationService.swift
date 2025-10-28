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
        await setupActivityNotificationSubscription()
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

    /// Subscribe to new Activity records for user-facing notifications
    /// Note: Query subscriptions are not allowed in shared database, so we rely on
    /// the shared database subscription to catch all changes, then filter activities
    /// in the notification handler (CloudKitSharedRecordsService)
    private func setupActivityNotificationSubscription() async {
        // NOTE: We don't create a separate activity subscription because:
        // 1. Query subscriptions are not allowed in shared database
        // 2. Database subscriptions catch all record types anyway
        // 3. We filter for CD_Activity records in the notification handler

        logger.info("ℹ️  Activity notifications are handled via shared database subscription")
    }
}
