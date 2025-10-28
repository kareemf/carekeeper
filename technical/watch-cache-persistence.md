# Watch Cache Persistence Spec

## Context
- watchOS app currently depends on in-memory `WatchDataProvider` state that is wiped on app relaunch.
- CloudKit fetches can take 60+ seconds, leaving users blocked from tracking activities after reboot.
- We already share data between iOS and watchOS via the app-group identifier `group.com.kareemf.CareKeeper`.

## Goals
- Restore Caree, Activity Type, and recent Activity data on watch launch without waiting for CloudKit.
- Continue to refresh data from CloudKit in the background and surface updated results seamlessly.
- Minimize memory usage while keeping the code localized to the watch target.

## Non-Goals
- No eviction policy or cache invalidation heuristics in v1 beyond full refresh.
- No changes to the iOS app data pipeline.
- No offline mutation conflict resolution beyond existing optimistic flows.

## Approach

### 1. Make Snapshots Codable
- Update `CareKeeper/Shared/Models/Snapshots.swift` to add `Codable` conformance to `CareeSnapshot`, `ActivityTypeSnapshot`, `ActivitySnapshot`, and `ActivitySnapshot.SyncState`.
- Use the default coding strategy (binary Data for images, ISO8601 dates via existing `Date` encoding).
- Verify that any computed properties remain transient and excluded from `Codable`.

### 2. Introduce `WatchCacheService`
- New file `CareKeeper/watchOS/Services/WatchCacheService.swift`.
- Access `UserDefaults(suiteName: CloudKitConfig.appGroupID)` mirroring `UserNotificationPreferences`.
- Namespaced keys:
  - `watch_carees`
  - `watch_activityTypes_<CAREeUUID>`
  - `watch_recentActivities_<CAREeUUID>`
- Public API:
  - `loadCarees()` / `saveCarees(_:)`
  - `loadActivityTypes(for:)` / `saveActivityTypes(_:for:)`
  - `loadRecentActivities(for:)` / `saveRecentActivities(_:for:)`
  - `clearAll()` compiled only for DEBUG to help with manual testing.
- Always return non-optional arrays (empty on cache miss) and log decode failures for observability.
- Keep everything on the main actor to align with `WatchDataProvider`.

### 3. Integrate Cache With `WatchDataProvider`
- Inject a `WatchCacheService` dependency (defaulted internally).
- On initialization:
  - Preload cached carees/activity types/recent activities into published properties.
  - Set `isRefreshingCarees`/`isRefreshingActivities[careeID]` flags before kicking off network refresh.
- Wrap existing CloudKit fetch tasks so they persist results back into the cache on success.
- Preserve optimistic mutation flows; cache updates happen once CloudKit confirms success.
- Maintain `activityTypesByCaree[careeID] == nil` as the signal that data is still loading.

### 4. Update watchOS Views
- `CareeListView.swift`: surface cached data immediately, show a lightweight indicator whenever `isRefreshingCarees` is true, and keep `.refreshable` to trigger a forced CloudKit refresh (which also rewrites the cache).
- `CareeDetailView.swift`: show cached activity types instantly when available, and add subtle status UI (e.g., overlay `ProgressView`) while fresh data loads.

## Testing & Validation
- Add snapshot encode/decode unit tests covering round-trips for each model.
- Add a `WatchCacheService` test verifying per-caree separation and behavior when the app-group defaults are unavailable (fallback path).
- Manual QA checklist:
  1. Launch watch app, allow data to load, then force-quit or reboot the watch simulator.
  2. Relaunch and confirm cached data appears instantly.
  3. Trigger `.refreshable` and confirm updates persist after relaunch.

## Rollout Considerations
- Cache size is bounded by small datasets (tens to hundreds of records) suitable for `UserDefaults`.
- Future iterations can add eviction/TTL logic if stale data becomes a concern.
