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
        let subscriptionID = "private-share-changes"
        let privateDatabase = container.privateCloudDatabase
        
        do {
            // Check if subscription already exists
            let existingSubscriptions = try await privateDatabase.allSubscriptions()
            if existingSubscriptions.contains(where: { $0.subscriptionID == subscriptionID }) {
                logger.info("✅ Private database share subscription already exists")
                return
            }

            // Create query subscription for CKShare records in private database
            let predicate = NSPredicate(value: true)
            let subscription = CKQuerySubscription(
                recordType: "cloudkit.share",
                predicate: predicate,
                subscriptionID: subscriptionID
            )
            subscription.notificationInfo = CKSubscription.NotificationInfo()
            subscription.notificationInfo?.shouldSendContentAvailable = true
            subscription.notificationInfo?.shouldBadge = false // Silent notification

            let savedSubscription = try await privateDatabase.save(subscription)
            logger.info("✅ Created private share subscription: \(savedSubscription.subscriptionID)")

        } catch {
            logger.error("❌ Error setting up private share subscription: \(error.localizedDescription)")
        }
    }
}
