# Fix: Post-CloudKit-Sync Regressions

**Status**: Complete
**Created**: 2026-02-28
**Branch**: `fix/creator-notification-identity`

---

## Context

After disabling SwiftData CloudKit mirroring (`cloudKitDatabase: .none`), CareeList and CareeDetailView now work correctly. Three regressions remain:

1. **Pending buffer dropped writes** — activities created during/after cache warm are silently lost
2. **ActivityListView "Load More"** — pagination resets on every cache mutation, items flicker, performance degrades
3. **Reminder metadata batch limit** — `CKFetchRecordsOperation` fails with 494 items (limit: 400)

---

## Fix 1: Pending Activity Buffer — Dropped Writes

**Files**: `CloudKitDataService.swift`, `CareeDetailView.swift`

### Root Cause

Race condition between `createActivity()` and `refreshOwnedCareesFromCloudKit()`:

1. `createActivity()` saves to CloudKit, caches locally, removes from pending buffer (line 704)
2. A concurrent `refreshOwnedCareesFromCloudKit()` calls `replaceCaree()` which **deletes ALL activities** then re-inserts from query results
3. If the query started before the CloudKit save propagated, the new activity is NOT in results → deleted from cache
4. Pending entry already removed → nothing to recover → **activity lost**

### Changes

**1a. Remove from pending only if confirmed in replaceCaree results, not eagerly** (lines 697-707)

Rather than never removing from pending (which would leave stale entries indefinitely), remove from pending only AFTER confirming the activity exists in the cache post-`replaceCaree`. Keep the eager cache write (it helps if no refresh is in flight), but defer the pending removal.

```swift
// BEFORE
try await cacheService.cacheActivity(syncedActivity, for: cachedCaree, activityTypeID: cachedActivityType.id)
pendingActivityBuffer?.remove(activityID: syncedActivity.id, careeID: caree.id)

// AFTER — cache eagerly but defer pending removal to applyPendingActivityMutations
do {
    try await cacheService.cacheActivity(syncedActivity, for: cachedCaree, activityTypeID: cachedActivityType.id)
    logger.info("✅ Activity cached locally (pending retained until next refresh confirms)")
} catch {
    logger.warning("⚠️ Failed to cache activity locally: \(error.localizedDescription)")
}
// Trigger a refresh so applyPendingActivityMutations runs soon
Task.detached(priority: .utility) { [weak self] in
    try? await self?.refreshOwnedCareesFromCloudKit()
}
```

The `Task.detached` refresh guarantees `applyPendingActivityMutations()` runs within seconds of the create, even if no other refresh is scheduled. This addresses Codex review issue #1 (stale pending entries).

**1b. Move `applyPendingActivityMutations()` inside `withBatch`** (lines 1155-1157)

```swift
// BEFORE
await cacheService.withBatch {
    // ... replaceCaree calls ...
}
await applyPendingActivityMutations()  // runs AFTER batch, after cacheRevision fires

// AFTER
await cacheService.withBatch {
    // ... replaceCaree calls ...
    await applyPendingActivityMutations()  // inside batch, same cacheRevision
}
```

**1c. Gate pending removal on CloudKit-confirmed inclusion** (lines 1165-1195 in `applyPendingActivityMutations`)

Pass the set of activity IDs returned by the CloudKit query into `applyPendingActivityMutations()`. Only remove pending entries for activities confirmed in those results. If the activity isn't in CloudKit results yet (eventual consistency), keep it in pending and re-cache it so `replaceCaree`'s delete doesn't lose it.

```swift
// Updated call site (inside withBatch):
let confirmedActivityIDs = Set(activityTypeIDByActivity.keys)
await applyPendingActivityMutations(confirmedIDs: confirmedActivityIDs)

// Updated method:
private func applyPendingActivityMutations(confirmedIDs: Set<UUID>) async {
    guard let pendingActivityBuffer, let cacheService else { return }
    for careeID in pendingActivityBuffer.pendingCareeIDs {
        guard let cachedCaree = cacheService.getCachedCaree(id: careeID) else { continue }
        let cachedTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
        let typeByID = Dictionary(uniqueKeysWithValues: cachedTypes.map { ($0.id, $0) })
        let mutations = pendingActivityBuffer.pendingMutations(for: careeID)
        if mutations.isEmpty { continue }
        await cacheService.withBatch {
            for mutation in mutations {
                if confirmedIDs.contains(mutation.id) {
                    // Confirmed in CloudKit query — replaceCaree already inserted it. Safe to remove.
                    pendingActivityBuffer.remove(activityID: mutation.id, careeID: careeID)
                } else if let cachedType = typeByID[mutation.activityTypeID] {
                    // Not yet confirmed — re-cache it (replaceCaree may have deleted it). Keep pending.
                    do {
                        try await cacheService.cacheActivity(
                            mutation.activity, for: cachedCaree, activityTypeID: cachedType.id)
                    } catch {
                        logger.warning("⚠️ Failed to re-cache pending activity \(mutation.id)")
                    }
                }
            }
        }
    }
}
```

**1d. Fix `displayActivityCount` double-counting** (CareeDetailView.swift line 701-704)

`displayActivityCount` adds `pendingCount` on top of `activityCount` without deduplication. Since pending entries now persist longer, this will double-count activities that exist in both cache and pending buffer.

```swift
// BEFORE
private func displayActivityCount(for caree: Caree) -> Int {
    let pendingCount = pendingActivityBuffer.pendingActivities(for: caree.id).count
    return (activityCount ?? 0) + pendingCount
}

// AFTER — only count pending entries not already in cache
private func displayActivityCount(for caree: Caree) -> Int {
    let cachedIDs = Set((caree.activities ?? []).map(\.id))
    let uniquePendingCount = pendingActivityBuffer.pendingActivities(for: caree.id)
        .filter { !cachedIDs.contains($0.id) }
        .count
    return (activityCount ?? 0) + uniquePendingCount
}
```

---

## Fix 2: ActivityListView "Load More" Regression

**File**: `CareKeeper/iOS/Views/Activity/ActivityListView.swift`

### Root Cause

The `cacheRevision` observer (lines 176-180) calls `loadInitialPage()` on **every** cache mutation app-wide. `loadInitialPage()` resets all pagination state (activityIDs, loadedActivityIDSet, cursor, hasMorePages) and reloads only page 1. User scrolls to page 3 → unrelated cache change → list snaps back to page 1 → flicker.

### Changes

**2a. Replace `cacheRevision` full-reset with incremental update** (lines 176-180)

```swift
// BEFORE
.onReceive(cacheService?.$cacheRevision...) { _ in
    Task { await loadInitialPage() }  // full reset!
}

// AFTER
.onReceive(cacheService?.$cacheRevision...) { _ in
    Task { await refreshCareeReference() }  // incremental update
}
```

**2b. Add `refreshCareeReference()` method**

New method that updates the `caree` reference without resetting pagination. Handles deleted activities (remove) and re-ordering from edits (re-sort loaded IDs). Uses a snapshot of known activity IDs at load time to distinguish truly new activities from merely unpaged ones.

```swift
// Snapshot of ALL activity IDs that existed at the time of the last loadInitialPage/loadNextPage.
// Activities not in this set but present in caree.activities are truly new (created after load).
@State private var knownActivityIDs: Set<UUID> = []

@MainActor
private func refreshCareeReference() async {
    guard let cacheService else { return }
    caree = cacheService.getCachedCaree(id: careeID)
    guard let caree, hasLoadedInitialPage else { return }

    let allActivities = caree.activities ?? []
    let allIDs = Set(allActivities.map(\.id))

    // Truly new = in caree.activities but NOT in the snapshot taken at last page load.
    // These are activities created/synced after we loaded — prepend them.
    // Unpaged activities (in knownActivityIDs but not loadedActivityIDSet) stay behind "Load More".
    let trulyNewIDs = allIDs.subtracting(knownActivityIDs)
    if !trulyNewIDs.isEmpty {
        let newActivities = allActivities
            .filter { trulyNewIDs.contains($0.id) }
            .sorted { $0.dateTime > $1.dateTime }
        activityIDs = newActivities.map(\.id) + activityIDs
        loadedActivityIDSet.formUnion(trulyNewIDs)
        knownActivityIDs.formUnion(trulyNewIDs)
    }

    // Remove deleted activities from loaded set
    let removedIDs = loadedActivityIDSet.subtracting(allIDs)
    if !removedIDs.isEmpty {
        activityIDs.removeAll { removedIDs.contains($0) }
        loadedActivityIDSet.subtract(removedIDs)
    }

    // Sync knownActivityIDs with reality — remove ALL deleted IDs, not just loaded ones.
    // Without this, IDs in the snapshot that were never loaded would linger indefinitely.
    knownActivityIDs.formIntersection(allIDs)

    // Re-sort loaded IDs to reflect any dateTime edits (Codex review i1#2)
    let idToActivity = Dictionary(uniqueKeysWithValues: allActivities.map { ($0.id, $0) })
    activityIDs.sort { lhs, rhs in
        guard let a = idToActivity[lhs], let b = idToActivity[rhs] else { return false }
        if a.dateTime != b.dateTime { return a.dateTime > b.dateTime }
        return a.id.uuidString > b.id.uuidString
    }

    // Update hasMorePages accounting for type filter (Codex review i1#3)
    let selectedTypeID = selectedActivityType?.id
    let filteredTotal: Int = if let typeID = selectedTypeID {
        allActivities.filter { $0.activityType?.id == typeID }.count
    } else {
        allActivities.count
    }
    let loadedFilteredCount: Int = if let typeID = selectedTypeID {
        activityIDs.filter { id in
            idToActivity[id]?.activityType?.id == typeID
        }.count
    } else {
        activityIDs.count
    }
    hasMorePages = loadedFilteredCount < filteredTotal
}
```

Also snapshot `knownActivityIDs` in `loadInitialPage()` and `loadNextPage()`:
```swift
// In loadInitialPage(), after resetting state:
knownActivityIDs = Set((caree?.activities ?? []).map(\.id))

// In loadNextPage(), no change needed — knownActivityIDs already captured at initial load.
// It represents the universe of activities at page-load time.
```

**Why `knownActivityIDs` instead of `newestSeenDate`**: A timestamp-based approach has two gaps (Codex review i3): (1) when the list starts empty, there's no timestamp to compare against, so new activities never prepend; (2) a type filter can miss activities with timestamps older than the global max. The ID-set approach avoids both — any activity ID not in the snapshot at load time is definitionally "new", regardless of timestamp or type.

**2c. Optimize `loadNextPage()` sort** (lines 365-375)

Filter before sorting to reduce sort input size:

```swift
// BEFORE: sort ALL activities, then filter by type, then filter by cursor
let sorted = (caree.activities ?? []).sorted { ... }  // sorts 494 items
let typeFiltered = sorted.filter { ... }
let page = typeFiltered.filter { $0.dateTime <= cursorDate }

// AFTER: filter first, sort the remainder
let allActivities = caree.activities ?? []
let typeFiltered: [Activity] = if let typeID = selectedTypeID {
    allActivities.filter { $0.activityType?.id == typeID }
} else { allActivities }
let cursorFiltered: [Activity] = if let cursorDate {
    typeFiltered.filter { $0.dateTime <= cursorDate }
} else { typeFiltered }
let sorted = cursorFiltered.sorted { lhs, rhs in
    if lhs.dateTime != rhs.dateTime { return lhs.dateTime > rhs.dateTime }
    return lhs.id.uuidString > rhs.id.uuidString
}
```

---

## Fix 3: Reminder Metadata Batch Limit

**File**: `CareKeeper/Shared/Services/ActivityReminderMetadataStore.swift`

### Root Cause

`CKFetchRecordsOperation` has a 400-item limit. With 494 activities, the entire fetch fails. Same batch pattern already used elsewhere in the codebase for `modifyRecords`.

### Changes

**3a. Split `fetchMetadata` into batches** (lines 101-156)

Extract the existing continuation-based fetch into `fetchMetadataBatch()`, loop with stride of 400:

```swift
func fetchMetadata(for activityIDs: [UUID]) async throws -> [UUID: ActivityReminderMetadata] {
    guard !activityIDs.isEmpty else { return [:] }
    try await ensureZoneExists()

    let batchSize = 400
    var allMetadata: [UUID: ActivityReminderMetadata] = [:]
    for batchStart in stride(from: 0, to: activityIDs.count, by: batchSize) {
        let batch = Array(activityIDs[batchStart..<min(batchStart + batchSize, activityIDs.count)])
        let result = try await fetchMetadataBatch(for: batch)
        allMetadata.merge(result) { _, new in new }
    }
    return allMetadata
}

private func fetchMetadataBatch(for activityIDs: [UUID]) async throws -> [UUID: ActivityReminderMetadata] {
    // existing withCheckedThrowingContinuation code moved here unchanged
}
```

No caller changes needed — batching is internal to the method.

---

## Implementation Order

1. **Fix 3** (simplest, isolated) — batch the fetch
2. **Fix 1** (pending buffer) — defer removal, move apply inside batch, verify existence, fix double-count
3. **Fix 2** (pagination) — incremental refresh with re-sort, filter-aware hasMorePages, optimize sort

## Files Modified

| File | Fix |
|------|-----|
| `CareKeeper/Shared/Services/ActivityReminderMetadataStore.swift` | 3: Batch fetchMetadata |
| `CareKeeper/iOS/Services/CloudKitDataService.swift` | 1: Pending buffer timing |
| `CareKeeper/iOS/Views/Caree/CareeDetailView.swift` | 1d: Fix displayActivityCount double-counting |
| `CareKeeper/iOS/Views/Activity/ActivityListView.swift` | 2: Pagination reset |

## Verification

1. Create activity during cold start → activity persists after cache warm
2. Create activity, pull-to-refresh → activity still visible (not dropped by replaceCaree)
3. Activity count in CareeDetailView header matches actual count (no double-counting)
4. Scroll to page 3+, create activity on different caree → list stays at current position
5. "Load More" → items appear and stay, no flicker
6. Edit activity dateTime → list re-sorts correctly without full reset
7. Filter by activity type → "Load More" button shows/hides correctly based on filtered count
8. Caree with 400+ activities → no "batch limit" warning in logs
9. Delete activity → removed from list without resetting pagination

## Codex Review History

### Iteration 1 — ISSUES_FOUND (3 issues)

1. **High**: Fix 1 can leave successful creates in pending indefinitely if no refresh runs soon
   - **Resolution**: Added `Task.detached` refresh trigger after successful CloudKit save (1a)
2. **High**: Fix 2's `refreshCareeReference()` misses in-place activity edits that change ordering
   - **Resolution**: Added re-sort of `activityIDs` using current `idToActivity` lookup (2b)
3. **Medium**: Fix 2's `hasMorePages` is incompatible with type-filtered pagination
   - **Resolution**: Compute `hasMorePages` using filtered counts matching current `selectedActivityType` (2b)

### Iteration 2 — ISSUES_FOUND (2 issues)

1. **High**: `refreshCareeReference()` adds ALL unpaged activities via `allIDs.subtracting(loadedActivityIDSet)`, collapsing pagination
   - **Resolution**: Track `newestSeenDate`; only prepend activities newer than anything previously loaded
2. **High**: Pending removal gated on local cache check, not CloudKit-confirmed inclusion — stale refresh can still delete
   - **Resolution**: Pass `confirmedIDs` (from CloudKit query results) into `applyPendingActivityMutations()`

### Iteration 3 — ISSUES_FOUND (1 issue, Fixes 1 & 3 approved)

1. **High**: `newestSeenDate` stays nil when list starts empty (new activities never prepend); not filter-aware (misses activities for specific types if global max timestamp is from another type)
   - **Resolution**: Replaced `newestSeenDate` with `knownActivityIDs: Set<UUID>` snapshot. Captured at `loadInitialPage()` time. Any ID not in the snapshot is definitionally "new" regardless of timestamp or type filter

### Iteration 4 — ISSUES_FOUND (1 minor issue, approach approved)

1. **Medium**: `knownActivityIDs` deletion incomplete — IDs in snapshot but never loaded are never removed when deleted upstream, causing drift
   - **Resolution**: Replace selective `knownActivityIDs.subtract(removedIDs)` with `knownActivityIDs.formIntersection(allIDs)` to sync with reality on every refresh

### Iteration 5 — APPROVED (plan logic confirmed sound)

Codex verified the formIntersection fix and confirmed all three fixes are logically correct. Noted that code changes haven't been applied yet (expected — this is plan review, not implementation review). Ready for implementation.

---

## Post-Implementation Notes

### Additional fixes discovered during implementation

1. **Load More regression (`knownCacheActivityIDs`)**: After implementing the `knownActivityIDs` approach from the spec (renamed to `knownCacheActivityIDs`), testing revealed that `refreshCareeReference()` was still collapsing pagination when background syncs added activities that predated the view session. Fixed by tracking all cache IDs at initial load and only prepending IDs genuinely absent from the snapshot.

2. **Refresh coalescing**: Not in the original spec. During cold start, multiple `.task` / `.onReceive` handlers fired simultaneously, causing redundant `refreshOwnedCareesFromCloudKit()` calls. Added `activeRefreshTask` / `refreshRequestedDuringRun` coalescing in `CloudKitDataService` to collapse concurrent refresh requests into at most two passes (current + follow-up).

3. **`displayActivityCount` dedup (Fix 1d)**: Pending activities that had already been cached were double-counted in the CareeDetailView header. Fixed by filtering pending activities against cached IDs before adding to the count.

4. **Diagnostic logs**: Verbose emoji-prefixed logs (`📋 [LIST]`, `🔵 [PENDING]`, `🔄 [REFRESH]`, `🗑️ [REPLACE]`) were added during debugging and removed in the cleanup pass. Warnings for real issues (caree not in cache, activityType not in cache) and coalescing info logs were retained.
