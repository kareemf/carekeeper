# Caregiver Display Names for Push Notifications

## Overview and Motivation

Currently, push notifications for shared caree activities read: "Another caregiver logged Nap at 10:14 AM". This is unhelpful when multiple caregivers share a caree — you cannot tell who performed the activity without opening the app. This spec adds caregiver display names so notifications read something like "Sarah logged Nap at 10:14 AM".

The approach stores the display name in two places:
1. **App group UserDefaults** — so both iOS and watchOS can read it locally
2. **`CD_creatorDisplayName` field on CD_Activity CKRecords** — so the name travels with the activity and is available at notification time without extra CloudKit lookups

## Storage Design

### App Group UserDefaults (local)

Follow the exact pattern in `UserNotificationPreferences.swift`:

- **Key**: `"caregiverDisplayName"` in app group `CloudKitConfig.appGroupID`
- **Service**: New class `CaregiverDisplayNameService`
- **Location**: `/CareKeeper/Shared/Services/CaregiverDisplayNameService.swift` (shared between iOS and watchOS targets)

```swift
@MainActor
class CaregiverDisplayNameService: ObservableObject {
    static let shared = CaregiverDisplayNameService()

    private let appGroupDefaults: UserDefaults
    private enum Keys {
        static let displayName = "caregiverDisplayName"
        static let hasBeenPrompted = "caregiverDisplayNamePrompted"
    }

    @Published var displayName: String? {
        didSet { appGroupDefaults.set(displayName, forKey: Keys.displayName) }
    }

    var hasDisplayName: Bool { displayName != nil && !displayName!.isEmpty }

    /// Returns displayName if set, otherwise fallback
    var resolvedDisplayName: String {
        if let name = displayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "A caregiver"
    }

    var shouldPromptForDisplayName: Bool {
        !hasDisplayName && !appGroupDefaults.bool(forKey: Keys.hasBeenPrompted)
    }

    func markPrompted() {
        appGroupDefaults.set(true, forKey: Keys.hasBeenPrompted)
    }

    private init() {
        if let defaults = UserDefaults(suiteName: CloudKitConfig.appGroupID) {
            self.appGroupDefaults = defaults
        } else {
            self.appGroupDefaults = .standard
        }
        self.displayName = self.appGroupDefaults.string(forKey: Keys.displayName)
    }
}
```

Key design decisions:
- Singleton pattern matches `UserNotificationPreferences.shared`
- `@Published` so SwiftUI views can react to changes
- App group storage for local persistence on each device
- `resolvedDisplayName` provides the fallback so callers never pass nil
- `shouldPromptForDisplayName` / `markPrompted()` ensure one-time prompt behavior

**Important**: App group UserDefaults does NOT sync between iOS and watchOS (they are separate physical devices). App groups only share between processes on the *same* device (e.g., iOS app ↔ iOS widget). Cross-device sync uses CloudKit — see below.

### CloudKit Cross-Device Sync

The display name is synced from iOS to watchOS via a `CD_UserSettings` record in the CloudKit private zone.

**Write (iOS)**: `CaregiverDisplayNameService.syncToCloudKit()` fires on every `displayName` change. Saves a `CD_UserSettings` record with:
- **Record ID**: `CD_UserSettings/displayName` (fixed, one per user)
- **Zone**: Private zone (`CloudKitConfig.zoneName`)
- **Field**: `CD_value` = the display name string

**Read (iOS and watchOS)**: `CaregiverDisplayNameService.fetchFromCloudKit()` fetches the record. On iOS, called at app launch when no local cache (reinstall recovery). On watchOS, called by `WatchDataProvider.loadCarees()` when no local cache exists or on pull-to-refresh.

### Caching Strategy

Display names change rarely (set once, maybe edited occasionally), so the caching strategy prioritizes avoiding unnecessary CloudKit operations over real-time propagation.

#### iOS: Debounced writes

`CaregiverDisplayNameService.syncToCloudKit()` (called from `displayName`'s `didSet`) uses a 2-second debounce to coalesce rapid keystrokes from the SharingView TextField into a single CloudKit write. Typing "Sarah" produces 1 CloudKit round-trip, not 5.

For explicit save actions (e.g., the display name prompt's Save button), `syncToCloudKitImmediately()` bypasses the debounce and writes immediately. This ensures the name is available in CloudKit right away when the user has deliberately confirmed it.

#### watchOS: Cache-first with pull-to-refresh invalidation

On initial launch, the watch uses the display name cached in local UserDefaults (persisted from the last CloudKit fetch). A CloudKit fetch only occurs when:

1. **No cached name** (`!hasDisplayName`) — first launch or fresh install
2. **Pull-to-refresh** on CareeListView — user explicitly requests fresh data (calls `loadCarees(force: true)`)

This avoids adding latency to normal app launches. The trade-off: if a user changes their name on iOS, the watch won't pick it up until the next pull-to-refresh. This is acceptable because display name changes are rare and pull-to-refresh is a natural "give me fresh data" gesture.

When a remote value is fetched, it is compared to the local cache and only written if different, avoiding unnecessary UserDefaults writes and `@Published` change notifications.

#### iOS: Read-back on launch when no local cache

On app launch, if no display name is cached locally (`!hasDisplayName`), iOS fetches from CloudKit via `CaregiverDisplayNameService.fetchFromCloudKit()`. This handles the reinstall scenario — the user previously set a name, uninstalled, and reinstalled. Without this, the app would re-prompt for a name that already exists in CloudKit.

This is not multi-device sync (no cache invalidation or periodic polling). iOS remains the single writer — this is purely a recovery read when local state is lost.

### CloudKit Schema Change

Add a new string field `CD_creatorDisplayName` to the `CD_Activity` record type.

- **Type**: String (nullable)
- **When set**: At activity creation time only (not updated retroactively)
- **Value**: The creator's display name from `CaregiverDisplayNameService.shared.resolvedDisplayName`

This field does NOT need to be added to the SwiftData `Activity` model since it is only used for notification display, not stored locally. It lives only on the CKRecord.

## CloudKit Record Changes

### iOS: `CloudKitRecordConverter.activityToRecord()`

**File**: `/CareKeeper/iOS/Services/CloudKitRecordConverter.swift` (line ~157)

After setting `CD_creatorUserRecordID`, add:

```swift
record["CD_creatorDisplayName"] = CaregiverDisplayNameService.shared.resolvedDisplayName as CKRecordValue
```

### watchOS: `SelectiveCloudKitService.createActivity()`

**File**: `/CareKeeper/watchOS/Services/SelectiveCloudKitService.swift` (line ~509)

After the existing `record["CD_creatorUserRecordID"]` line, add:

```swift
record["CD_creatorDisplayName"] = CaregiverDisplayNameService.shared.resolvedDisplayName
```

## Notification Resolution Changes

There are **three** call sites where notifications are built, and all have the `CKRecord` available. At each site, replace the hardcoded `"Another caregiver"` with a read from the record:

### Pattern (same at all three sites)

```swift
let creatorDisplayName = record["CD_creatorDisplayName"] as? String ?? "A caregiver"
```

Then pass `creatorDisplayName` to `presentNewActivityNotification(creatorName:)`.

### Site 1: `CloudKitSharedRecordsService.handleNewActivityNotification()` (line ~237)

**File**: `/CareKeeper/iOS/Services/CloudKitSharedRecordsService.swift`

### Site 2: `CloudKitSharedRecordsService.notifyForActivityRecord()` (line ~401)

**File**: `/CareKeeper/iOS/Services/CloudKitSharedRecordsService.swift`

### Site 3: `CloudKitDataService` private zone notification handler (line ~1675)

**File**: `/CareKeeper/iOS/Services/CloudKitDataService.swift`

### Default value change

**File**: `/CareKeeper/Shared/Services/UserNotificationService.swift` (line ~129)

Update default parameter from `"Another caregiver"` to `"A caregiver"` for consistency.

## UI Changes

### 1. SharingView: "Your Display Name" field

**File**: `/CareKeeper/iOS/Views/Sharing/SharingView.swift`

Add a new section at the top of the `List` (before "Shared by Me"):

```swift
Section {
    HStack {
        Text("Your Display Name")
        Spacer()
        TextField("Enter your name", text: Binding(
            get: { displayNameService.displayName ?? "" },
            set: { displayNameService.displayName = $0.isEmpty ? nil : $0 }
        ))
        .multilineTextAlignment(.trailing)
        .textContentType(.name)
    }
} header: {
    Text("Your Identity")
} footer: {
    Text("This name is shown to other caregivers in activity notifications.")
}
```

Add `@StateObject private var displayNameService = CaregiverDisplayNameService.shared` to the view.

### 2. One-Time Display Name Prompt

**New file**: `/CareKeeper/iOS/Components/DisplayNamePromptView.swift`

An `.alert` with a `TextField` (iOS 16+):
- Title: "Set Your Display Name"
- Message: "Other caregivers will see this name in notifications when you track activities."
- A `TextField` for the name
- "Save" and "Skip" buttons

The prompt only appears once. Uses `CaregiverDisplayNameService.shared.shouldPromptForDisplayName` as guard. Both "Save" and "Skip" call `markPrompted()`.

### 3. Prompt Trigger Points

#### Trigger A: When sharing a caree (owner sharing flow)

**File**: `/CareKeeper/iOS/Components/CareeShareButton.swift`

In `prepareShare()`, before opening the `CloudSharingView`, check if display name is set:

```swift
private func prepareShare() async {
    if CaregiverDisplayNameService.shared.shouldPromptForDisplayName {
        showingDisplayNamePrompt = true
        return  // Continue to share after prompt is dismissed
    }
    // ... existing share logic
}
```

After prompt dismissal, proceed with the share flow.

#### Trigger B: When tracking an activity on a shared caree

**File**: `/CareKeeper/iOS/Views/Activity/TrackActivityView.swift`

In `saveActivity()`, before the actual save, check if:
1. The caree is shared
2. Display name is not yet set and user hasn't been prompted

```swift
private func saveActivity() {
    guard let activityType = selectedActivityType else { return }

    if isSharedCaree && CaregiverDisplayNameService.shared.shouldPromptForDisplayName {
        showingDisplayNamePrompt = true
        return  // Will retry save after prompt
    }
    // ... existing save logic
}
```

#### Trigger flow summary

The prompt shows at most once across the lifetime of the app. Once `markPrompted()` is called (via Save or Skip), no trigger point shows the prompt again. The user can always edit their name in SharingView.

### 4. watchOS: No prompt, read-only

No UI changes on watchOS. The watch reads `CaregiverDisplayNameService.shared.resolvedDisplayName` from app group UserDefaults when creating activities. If not set, falls back to "A caregiver".

## Implementation Checklist

### Step 1: Storage service
- [x] Create `CaregiverDisplayNameService` in `/CareKeeper/Shared/Services/CaregiverDisplayNameService.swift`
- [x] Add to both iOS and watchOS targets (already in `Shared/Services`, included by `project.yml`)
- [x] Add `init(testing:)` for isolated unit tests

### Step 2: CloudKit schema — write side
- [x] In `CloudKitRecordConverter.activityToRecord()`, add `record["CD_creatorDisplayName"]`
- [x] In `SelectiveCloudKitService.createActivity()`, add `record["CD_creatorDisplayName"]`

### Step 3: Notification resolution — read side
- [x] In `CloudKitSharedRecordsService.handleNewActivityNotification()`, read `CD_creatorDisplayName` from record
- [x] In `CloudKitSharedRecordsService.notifyForActivityRecord()`, read `CD_creatorDisplayName` from record
- [x] In `CloudKitDataService` private zone notification handler, read `CD_creatorDisplayName` from record
- [x] Update default parameter in `UserNotificationService.presentNewActivityNotification()` from "Another caregiver" to "A caregiver"

### Step 4: UI — SharingView display name field
- [x] Add "Your Identity" section at top of `SharingView` list
- [x] Wire up `TextField` to `CaregiverDisplayNameService.shared`

### Step 5: UI — Display name prompt
- [x] Create `DisplayNamePromptModifier` (alert with text field, `.displayNamePrompt()` view modifier)
- [x] Add prompt trigger in `CareeShareButton.prepareShare()` (owner sharing flow)
- [x] Add prompt trigger in `TrackActivityView.saveActivity()` (shared caree activity tracking)
- [x] Ensure prompt only shows once via `shouldPromptForDisplayName` / `markPrompted()`

### Step 6: CloudKit cross-device sync
- [x] Add `syncToCloudKit()` to `CaregiverDisplayNameService` — saves `CD_UserSettings` record on display name change
- [x] Add `fetchFromCloudKit()` to `CaregiverDisplayNameService` — shared read logic for iOS and watchOS
- [x] iOS: fetch display name on app launch when no local cache (reinstall recovery) in `CareKeeperApp`
- [x] watchOS: fetch display name in `WatchDataProvider.loadCarees()` on startup when not cached or on pull-to-refresh
- [x] Remove `fetchDisplayName()` from `SelectiveCloudKitServiceProtocol` (consolidated into shared service)

### Step 6b: Caching strategy
- [x] Add 2-second debounce to `syncToCloudKit()` for SharingView TextField keystroke coalescing
- [x] Add `syncToCloudKitImmediately()` for explicit Save actions (DisplayNamePromptModifier)
- [x] Extract `performCloudKitSync()` shared implementation
- [x] Update `WatchDataProvider.loadCarees()` to fetch display name on pull-to-refresh (`force`) or no cache
- [x] Compare remote vs local before updating to avoid unnecessary writes
- [x] Update spec with caching strategy section

### Step 7: Fix watchOS self-notification bug
- [x] Fix `CloudKitNotificationAuthorFilter` to treat `CKCurrentUserDefaultName` as unreliable fallback
- [x] When `CD_creatorUserRecordID` is `__defaultOwner__`, fall through to `record.creatorUserRecordID` metadata

### Step 8: Testing
- [x] Unit test `CaregiverDisplayNameService` (read/write, fallback, prompted flag, persistence)
- [x] Unit test `CloudKitNotificationAuthorFilter` — expanded to 8 cases covering `CKCurrentUserDefaultName` fallback
- [ ] Verify `CD_creatorDisplayName` is set on activities created from iOS (manual/device testing)
- [ ] Verify `CD_creatorDisplayName` is set on activities created from watchOS (manual/device testing)
- [ ] Verify notification body shows creator name when field is present (manual/device testing)
- [ ] Verify notification body shows "A caregiver" when field is absent — backward compatibility (manual/device testing)
- [ ] Verify prompt appears on first share attempt without display name (manual/device testing)
- [ ] Verify prompt appears on first activity track on shared caree without display name (manual/device testing)
- [ ] Verify prompt does not appear after being dismissed — skip or save (manual/device testing)
- [ ] Verify SharingView shows editable display name field (manual/device testing)
- [ ] Verify watchOS no longer receives self-notifications for own activities (manual/device testing)

## Edge Cases and Considerations

### watchOS self-notification bug (fixed)
When the watch creates an activity, `SelectiveCloudKitService` calls `fetchCurrentUserRecordName()` which may return `nil` (network issues on watch). The fallback writes `CKCurrentUserDefaultName` (`"__defaultOwner__"`) as `CD_creatorUserRecordID`. On iOS, the filter previously saw this field didn't match the real user ID and short-circuited to "notify", ignoring the CloudKit `record.creatorUserRecordID` metadata which correctly identifies the same user. Fix: `CloudKitNotificationAuthorFilter` now treats `CKCurrentUserDefaultName` as unreliable and falls through to check `record.creatorUserRecordID`.

### Backward compatibility
Activities created before this feature will not have `CD_creatorDisplayName`. The notification code falls back to "A caregiver" when the field is nil. This is an improvement over the current "Another caregiver" since it does not imply we know there is a different person — we simply do not know.

### Name changes
If a user changes their display name in SharingView, only **future** activities carry the new name. Existing activity records retain the old name. This is acceptable since notifications are ephemeral and the name was correct at the time of activity creation.

### Empty or whitespace-only names
`resolvedDisplayName` trims whitespace and returns "A caregiver" for empty/whitespace-only strings. The `TextField` in SharingView allows clearing the name (sets to nil).

### watchOS without iOS setup
If a user only uses the watch and never sets their display name on iOS, activities will be attributed to "A caregiver". The user must set their name on iOS. The watch does not prompt but will pick up the name from CloudKit on next launch.

### Multiple iOS devices
The display name is stored in app group UserDefaults locally and synced via CloudKit. All devices (iOS and watchOS) read from the same `CD_UserSettings/displayName` CloudKit record. Setting the name on any iOS device propagates to all devices via CloudKit.

### App group UserDefaults does NOT sync cross-device
App groups only share data between processes on the same physical device (e.g., iOS app ↔ iOS widget). iPhone and Apple Watch are separate devices, so app group UserDefaults does NOT sync between them. This is why CloudKit sync was added for the display name. The same limitation affects `UserNotificationPreferences` — watchOS toggles write to the watch's local UserDefaults and are not visible to iOS (separate issue, separate spec).

### Privacy
Display names are stored as plain strings on CKRecords, visible to all share participants. This is consistent with how CloudKit sharing works (participants can already see each other's names via CKShare.Participant). The user explicitly enters this name knowing it will be shown to other caregivers.

### CloudKit schema deployment
The `CD_creatorDisplayName` field will be auto-created in the Development environment when the first record with this field is saved. For Production, the schema must be promoted via CloudKit Dashboard before the App Store release.

### Prompt UX
The "Skip" option on the prompt is non-aggressive. If the user skips, `markPrompted()` is called and the prompt will not appear again. The user can always set their name later via SharingView's "Your Identity" section.
