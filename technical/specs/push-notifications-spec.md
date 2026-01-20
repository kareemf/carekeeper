# Push Notifications for Shared Activity Updates

**Status**: Planned (Not Yet Implemented)
**Created**: 2025-10-11
**Estimated Effort**: ~8 hours

## Overview

Add opt-in push notifications to alert users when other caregivers create new activities on shared carees. This enables real-time coordination between caregivers without requiring them to manually check for updates.

## User Story

> As a caregiver using a shared caree,
> I want to receive notifications when other caregivers log new activities,
> So that I can stay informed about the caree's care in real-time.

## Current State

### What's Already Working
- ✅ Silent background CloudKit notifications (database subscriptions)
- ✅ AppDelegate receives remote notifications from CloudKit
- ✅ CloudKitSharedRecordsService auto-refreshes data on CloudKit changes
- ✅ Automatic data sync without user intervention

### What's Missing
- ❌ No user-facing notifications
- ❌ No creator tracking on activities (can't distinguish who created what)
- ❌ No user preferences for opt-in/opt-out
- ❌ No notification permission handling

## Architecture

### Solution Components

#### 1. User Preferences Service
**New File**: `CareKeeper/Services/UserNotificationPreferences.swift`

Responsibilities:
- Store global notification enabled/disabled flag
- Store per-caree notification preferences (opt-in for specific carees)
- Use UserDefaults with app group for iOS/watchOS sync
- Provide observable interface for UI binding

```swift
class UserNotificationPreferences: ObservableObject {
    @AppStorage("notificationsEnabled", store: appGroupDefaults)
    var notificationsEnabled: Bool = false

    private let careePreferencesKey = "notificationsPerCaree"

    func isEnabled(for careeID: UUID) -> Bool
    func setEnabled(_ enabled: Bool, for careeID: UUID)
}
```

#### 2. Activity Creator Tracking
**Modify**: `CloudKitSharedDataService.swift`

Changes needed:
- Add `CD_creatorUserRecordID` field when creating activities
- Resolve the **real** CloudKit user record ID via `CKContainer.fetchUserRecordID`
- Store the creator's record name for filtering
- **No backfill/migration** for existing records; only new activities will carry the correct creator ID

```swift
// In convertActivityToRecord():
let recordID = try await container.fetchUserRecordID()
record["CD_creatorUserRecordID"] = recordID.recordName
```

#### 3. Local Notification Service
**New File**: `CareKeeper/Services/UserNotificationService.swift`

Responsibilities:
- Request UNUserNotificationCenter permissions
- Present local notifications for new shared activities
- Format notification content (title, body, badge)
- Handle notification taps to deep link to activity detail
- Manage notification categories and actions

```swift
@MainActor
class UserNotificationService: ObservableObject {
    func requestPermission() async -> Bool
    func presentNotification(for activity: Activity, caree: Caree, creator: String)
    func handleNotificationTap(activityID: UUID)
}
```

#### 4. Enhanced Notification Handling
**Modify**: `CloudKitSharedRecordsService.swift`

Enhancements:
- Parse CloudKit query notifications for new CD_Activity records
- Check user preferences before showing notification
- Compare creator ID to current user to exclude self
- Extract activity details from notification payload
- Call UserNotificationService to present notification

```swift
private func handleCloudKitNotification(_ notification: CKNotification) async {
    // Check if it's a query notification for activities
    guard let queryNotification = notification as? CKQueryNotification else { return }

    // Filter out user's own activities
    // Check user preferences
    // Present local notification if appropriate
}
```

#### 5. Settings UI

**iOS**:
- Global notification toggle in app settings or dedicated settings view
- Per-caree notification toggle in CareeDetailView toolbar/menu
- Info text explaining notification behavior
- Deep link to iOS Settings if permissions denied

**watchOS**:
- Per-caree toggle in CareeDetailView (simplified)
- Global toggle in settings (if space permits)
- Graceful handling of permission state

#### 6. CloudKit Subscription Enhancement
**Modify**: `CloudKitNotificationService.swift`

Changes:
- Add query subscription for CD_Activity records with alert notifications
- Configure notification info with title/body templates
- Set `shouldSendContentAvailable = true` for background processing
- Set `alertBody` and `alertLocalizationKey` for user-facing alerts
- Ensure zone-based subscriptions work correctly

```swift
private func setupActivityNotificationSubscription() async {
    let subscription = CKQuerySubscription(
        recordType: "CD_Activity",
        predicate: NSPredicate(value: true),
        subscriptionID: "shared-activity-alerts"
    )

    subscription.notificationInfo = CKSubscription.NotificationInfo()
    subscription.notificationInfo?.shouldSendContentAvailable = true
    subscription.notificationInfo?.alertBody = "New activity logged"
    // ... configure notification
}
```

## Implementation Plan

### Phase 1: Foundation (Core Infrastructure)
**Goal**: Set up the foundational services and data model

1. **Create UserNotificationPreferences.swift**
   - Implement UserDefaults-backed storage
   - Add @AppStorage properties for global toggle
   - Add methods for per-caree preferences
   - Use app group for iOS/watchOS sync

2. **Create UserNotificationService.swift**
   - Implement UNUserNotificationCenter wrapper
   - Add permission request flow
   - Add notification presentation method
   - Add notification tap handling (placeholder)

3. **Request notification permissions on app launch**
   - Update `CareKeeperApp.swift` to request permissions
   - Update watchOS app similarly
   - Handle permission denial gracefully

4. **Add creator tracking to activities**
   - Modify `CloudKitSharedDataService.createActivity()`
   - Add `CD_creatorUserRecordID` field to CKRecord
   - Store creator's **real** record name (from `fetchUserRecordID`)

### Phase 2: Notification Logic
**Goal**: Connect CloudKit notifications to local notifications

5. **Update CloudKitNotificationService**
   - Add query subscription for CD_Activity with alerts
   - Configure notification templates
   - Test subscription creation

6. **Enhance CloudKitSharedRecordsService**
   - Parse query notifications for new activities
   - Extract activity details from CKQueryNotification
   - Implement creator filtering logic (prefer `CD_creatorUserRecordID`, fallback to `record.creatorUserRecordID`)
   - Integrate with UserNotificationPreferences

7. **Implement notification presentation**
   - Format notification title/body with activity details
   - Add proper notification identifiers
   - Handle notification delivery
   - Test end-to-end notification flow

### Phase 3: UI (Settings)
**Goal**: Provide user controls for notification preferences

8. **Add notification toggle to iOS CareeDetailView**
   - Add toggle in toolbar or detail section
   - Bind to UserNotificationPreferences
   - Show permission state if denied
   - Provide link to iOS Settings

9. **Add notification toggle to watchOS CareeDetailView**
   - Add simplified toggle control
   - Handle limited screen space
   - Sync with iOS preferences

10. **Create settings view for global preferences (iOS)**
    - New NotificationSettingsView
    - Global enable/disable toggle
    - List of carees with individual toggles
    - Permission status display
    - Info/help text

### Phase 4: Testing & Polish
**Goal**: Ensure robust, production-ready feature

11. **Test notification flow end-to-end**
    - Test on physical devices (simulator limitations)
    - Test with multiple users and shared carees
    - Test opt-in/opt-out behavior
    - Test creator filtering

12. **Add notification tap handling**
    - Implement deep linking to activity detail
    - Handle app in background vs terminated state
    - Test navigation from notification

13. **Handle edge cases**
    - Permissions denied → show helpful message
    - Notifications disabled globally → respect setting
    - Network offline → queue for later
    - Rapid activity creation → batch or throttle

14. **Update documentation**
    - Add feature to CLAUDE.md
    - Document notification behavior
    - Add troubleshooting guide

## Technical Details

### UserDefaults Keys
```swift
// Global toggle (synced via app group)
"notificationsEnabled": Bool

// Per-caree preferences (Dictionary)
"notificationsPerCaree": [String: Bool] // UUID string keys
```

### CKRecord Schema Changes
```swift
CD_Activity:
  - CD_creatorUserRecordID: String (CKRecord.ID.recordName)
    // Stores the creator's CloudKit user record ID (real record name)
    // Used to filter out notifications for user's own activities
```

### Identity Resolution
```swift
CloudKitUserIdentityService:
  - Caches current user record name via CKContainer.fetchUserRecordID
  - Shared across iOS/watchOS services to avoid repeated lookups
```

### Notification Content Format
```swift
Title: "New activity for [Caree Name]"
Body: "[User Name] logged [Activity Type Name] at [Time]"
UserInfo: {
    "activityID": "[UUID]",
    "careeID": "[UUID]",
    "type": "newActivity"
}
```

### Permissions Flow
```
1. User enables notifications for a caree
   ↓
2. Check if permission granted
   ↓
3. If not granted → Request permission
   ↓
4. If denied → Show alert with link to Settings
   ↓
5. If granted → Enable notifications and save preference
```

### CloudKit Subscription Strategy
```
Existing:
- Database subscription for shared DB (silent, content-available)
- Database subscription for private DB (silent, content-available)

New:
- Query subscription for CD_Activity in shared zones (with alerts)
  - Predicate: All records (true)
  - NotificationInfo: Alert + content-available
  - Zone-specific or global? → Test both approaches
```

## Files to Create

1. `CareKeeper/Services/UserNotificationPreferences.swift`
   - UserDefaults-backed preference storage
   - Observable for SwiftUI binding
   - iOS + watchOS compatible

2. `CareKeeper/Services/UserNotificationService.swift`
   - UNUserNotificationCenter wrapper
   - Permission management
   - Notification presentation
   - Deep linking support

3. `CareKeeper/Views/Settings/NotificationSettingsView.swift` (iOS)
   - Global settings UI
   - Per-caree toggles
   - Permission status
   - Help text

## Files to Modify

1. **`CareKeeper/Services/CloudKitSharedDataService.swift`**
   - Add creator tracking in `createActivity()`
   - Store `CD_creatorUserRecordID` in CKRecord

2. **`CareKeeper/Services/CloudKitNotificationService.swift`**
   - Add query subscription for CD_Activity
   - Configure alert notifications
   - Handle subscription creation errors

3. **`CareKeeper/Services/CloudKitSharedRecordsService.swift`**
   - Parse CKQueryNotification in `handleCloudKitNotification()`
   - Extract activity details from notification
   - Check preferences and creator
   - Call UserNotificationService

4. **`CareKeeper/App/AppDelegate.swift`**
   - Add UNUserNotificationCenterDelegate conformance
   - Handle notification tap events
   - Forward to deep linking handler

5. **`CareKeeper/Views/Caree/CareeDetailView.swift`**
   - Add notification toggle in toolbar/menu
   - Show permission state
   - Link to settings if denied

6. **`CareKeeper Watch App/Views/CareeDetailView.swift`**
   - Add notification toggle (simplified)
   - Sync with UserNotificationPreferences

7. **`CLAUDE.md`**
   - Document the notification feature
   - Add to implementation status
   - Note any caveats or limitations

## Estimated Effort

- **Phase 1** (Foundation): ~2 hours
  - Create preference service
  - Create notification service
  - Add permission handling
  - Add creator tracking

- **Phase 2** (Notification Logic): ~3 hours
  - CloudKit subscription updates
  - Notification handling logic
  - Creator filtering
  - Testing notification flow

- **Phase 3** (UI): ~2 hours
  - iOS settings UI
  - watchOS settings UI
  - CareeDetailView toggles
  - Permission state handling

- **Phase 4** (Testing & Polish): ~1 hour
  - End-to-end testing
  - Deep linking
  - Edge case handling
  - Documentation

**Total Estimated Time**: ~8 hours

## Testing Checklist

- [ ] Notification permissions requested correctly
- [ ] Notification permissions denied handled gracefully
- [ ] Global toggle enables/disables all notifications
- [ ] Per-caree toggle works independently
- [ ] User's own activities don't trigger notifications
- [ ] Other users' activities DO trigger notifications
- [ ] Notification tap opens correct activity detail
- [ ] Notifications work on iOS
- [ ] Notifications work on watchOS
- [ ] Preferences sync between iOS and watchOS
- [ ] Notifications respect Do Not Disturb
- [ ] Notification format is clear and helpful
- [ ] Multiple rapid activities don't spam user

## Open Questions

1. **Notification throttling**: Should we batch notifications if multiple activities are logged quickly?
2. **Participant names**: How do we get the creator's display name from CKRecord.ID?
   - Option A: Query CKUserIdentity (requires special permissions)
   - Option B: Store creator name in activity record
   - Option C: Use "Another caregiver" as generic name
3. **Zone-specific vs global subscription**: Should we create one query subscription per zone or one global?
4. **Silent vs alert notifications**: Should CloudKit send alerts, or should we always use local notifications?
5. **Notification grouping**: Should notifications be grouped by caree or activity type?

## Future Enhancements

- **Rich notifications**: Show activity details in expanded notification
- **Notification actions**: Quick actions like "View" or "Acknowledge"
- **Activity feed**: In-app feed of recent shared activities
- **Daily digest**: Option for daily summary instead of real-time alerts
- **Smart notifications**: ML-based notification timing/frequency
- **Activity comments**: Reply to activities with comments/reactions

## References

- [Apple: UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [Apple: CloudKit Subscriptions](https://developer.apple.com/documentation/cloudkit/subscriptions)
- [Apple: Handling Notifications](https://developer.apple.com/documentation/usernotifications/handling_notifications_and_notification-related_actions)
- [Apple: App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
