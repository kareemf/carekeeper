# Cold Start Activity Buffer (iOS)

**Status**: Implemented  
**Created**: 2026-02-22  
**Author**: Codex  
**Audience**: iOS, CloudKit, SwiftData

---

## Problem Summary
- On cold start, the cache is still initializing while users can reach `TrackActivityView`.
- Owned activity creation can succeed in CloudKit but fail to enter the local cache when `getCachedCaree()` returns nil.
- The Caree detail UI depends on cache refresh signals that may not fire when only child relationships change.

## Goals
- **Correctness**: Never drop user-created activities during cold boot.
- **UI responsiveness**: Show new activities immediately, even if cache is cold.
- **No extra fetches**: When cache misses occur, enqueue instead of fetching.

## Design Overview
### Pending activity buffer
Introduce an in-memory buffer for owned activity mutations:
- `PendingActivityBuffer` stores pending activity creations keyed by caree ID.
- Activity creation enqueues immediately (before CloudKit save).
- Pending entries are merged into the cache after the initial owned refresh completes.
- Pending entries are removed once the cache write succeeds or the CloudKit save fails.

### UI merge layer
Views merge pending activities with cached activities:
- `CareeDetailView` uses a merged recent list for immediate visibility.
- `ActivityListView` merges pending activities into the paged list.
- Merging de-duplicates by activity ID and sorts by dateTime desc.

### Immediate refresh signal
Add a lightweight cache revision signal:
- `LocalCacheService.cacheRevision` increments on each cache mutation.
- Views listen to `cacheRevision` to re-resolve carees without waiting for debounced refresh.

### Hardened cache writes
When parents are missing in cache:
- **Do not fetch** from CloudKit.
- Keep the activity in the pending buffer.
- Apply it once the cache is ready after refresh.

## Data Flow (Owned Activity Creation)
1. User taps Save in `TrackActivityView`.
2. `CloudKitDataService.createActivity` creates a local Activity and enqueues it.
3. UI updates immediately via pending merge.
4. CloudKit save completes.
5. If cache is ready, the activity is cached and pending entry is removed.
6. If cache is not ready, pending entry is kept until refresh finishes.
7. `refreshOwnedCareesFromCloudKit` merges pending entries into cache in a batch.

## Implementation Notes
- New type: `PendingActivityBuffer` (in-memory only).
- `CloudKitDataService` owns the buffer reference and merges pending entries after refresh.
- `CareKeeperApp` wires the buffer into `CloudKitDataService` and SwiftUI environment.
- Pending entries are removed on successful delete as well.

## Out of Scope
- Persisting pending entries across app restarts.
- Shared caree flow (already uses immediate cache refresh + notifications).

## Validation Checklist
- Cold start: create activity before cache refresh completes → activity appears immediately.
- Warm start: activity appears immediately and remains after refresh.
- Deleting a pending activity removes it from UI and cache after delete succeeds.
