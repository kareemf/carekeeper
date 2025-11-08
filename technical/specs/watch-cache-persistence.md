# Watch Cache Persistence Spec

## Context
- watchOS app currently relies on in-memory `WatchDataProvider` state that is wiped on relaunch.
- CloudKit fetches can take over a minute, blocking users from tracking activities until queries finish.
- The shared app group identifier `group.com.kareemf.CareKeeper` is available to both iOS and watchOS targets but may occasionally fail to resolve.

## Goals
- Surface cached carees, activity types, and recent activities immediately on watch launch.
- Continue fetching fresh data from CloudKit and update the UI without blocking interactions.
- Fail gracefully when the app-group container is unavailable (no crashes, clear warnings).

## Non-Goals
- Cache eviction/TTL heuristics beyond wipe-on-clear.
- Changes to the iOS caching story.
- Resolving offline mutation conflicts.

## Approach

### 1. Make Snapshots Codable
- Add `Codable` conformance to `CareeSnapshot`, `ActivityTypeSnapshot`, `ActivitySnapshot`, and `ActivitySnapshot.SyncState` so they can persist as JSON blobs.

### 2. Introduce `WatchCacheService`
- `CareKeeper/watchOS/Services/WatchCacheService.swift` wraps app-group `UserDefaults` access.
- Expose `isAppGroupAvailable` and guard cache accesses so the service can log warnings and skip persistence when the container cannot be resolved.
- Namespaced keys:
  - `watch_carees`
  - `watch_activityTypes_<CAREeUUID>`
  - `watch_recentActivities_<CAREeUUID>`

### 3. Integrate Cache With `WatchDataProvider`
- On initialization, hydrate `WatchDataProvider` from the cache when the container is accessible; otherwise log a warning and proceed without persistence.
- Wrap every cache read/write with availability checks and warning logs rather than fatal errors.
- Maintain stale-while-revalidate behaviour: show cached data immediately, fetch CloudKit in the background, and update the UI when fresh data arrives.

### 4. Update Watch Views
- Keep list/detail views interactive while background refreshes run, surfacing existing `isRefreshing` indicators (already implemented in earlier work).

## Testing & Validation
- Snapshot encode/decode unit tests.
- Watch cache service tests that cover per-caree separation and fallback behaviour when the app group is unavailable.
- Manual QA: launch with cache, reboot watch, toggle app-group entitlement, confirm warnings and degraded behaviour without crashes.
