# Shared Zone Push Handling (Notifications)

Goal: deliver user-facing notifications for new `CD_Activity` in shared carees without relying on unsupported shared-db query subscriptions or broad “sweep every zone” fallbacks. Minimum OS: iOS 18 / watchOS 10.

## Decisions
- Use `CKRecordZoneSubscription` per shared zone (no shared query subscription).
- No fallback to database-wide sweeps if zone subs fail; log only.
- Store per-zone change tokens locally (per-device) via `UserDefaults` keyed by zoneID components.
- Continue honoring per-caree notification prefs and skip self-authored activities.

## Implementation Plan
1) Remove shared `CKQuerySubscription` setup
   - Keep private DB query sub for owners.
   - Drop `shared-activity-created` query subscription creation.
2) Add shared zone subscriptions
   - When enumerating shared zones (in `CloudKitSharedRecordsService.fetchSharedCarees`), ensure a `CKRecordZoneSubscription` exists for each non-default shared zone (ID prefix `shared-zone-<zoneName>-<owner>`). Ignore failures beyond logging.
   - Optionally prune subs for zones no longer present (best-effort).
3) Handle shared zone notifications
   - In `handleCloudKitNotification`, if `CKRecordZoneNotification` with `.shared` scope, fetch zone changes scoped to that zone only using stored change token.
   - Fetch changes via `CKFetchRecordZoneChangesOperation` (or async equivalent); update tokens mid-flight and on completion. On token-expired error, clear token for that zone.
   - For `CD_Activity` records returned:
     - Filter out current-user-created.
     - Skip if activity ID already in `sharedCarees`’ cached activities set (prevents duplicate alerts on updates).
     - Guard per-caree notification prefs.
     - Fetch caree record for name and activityType record for label (best-effort).
     - Call `UserNotificationService.presentNewActivityNotification`.
   - After processing, continue to trigger the existing shared refresh (`fetchSharedCarees`) so UI/cache stay in sync.
4) Token storage helper
   - Small struct inside `CloudKitSharedRecordsService` to read/write `CKServerChangeToken` per zoneID using `UserDefaults`.
5) Tests (scope)
   - Unit: minimal coverage added for zone notification plumbing (ensures per-zone handler triggers scoped change fetch + refresh) and share-acceptance refresher backoff. Further coverage for change-fetch -> notification emission still outstanding due to CloudKit dependencies.
   - Manual: two-account flow (owner + participant), create activity in shared caree; owner should receive banner. Optionally validate via CK Dashboard inserts.

## Out of Scope
- No global shared-db sweep fallback.
- No shared token storage across devices (per-device tokens only).***
