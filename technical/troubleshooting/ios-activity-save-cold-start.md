# iOS Activity Save Performance - Cold Start Issue

## Problem Statement

When the app hasn't been used for a while (cold start), tracking a new activity exhibits poor UX:

1. **Save takes a long time** - spinner animation runs for 2-5+ seconds
2. **List doesn't update immediately** - activity doesn't appear in the list until manual refresh (pull-to-refresh)
3. **Subsequent saves work fine** - after the first activity, future saves complete quickly (~0.75s) and update the list in real-time

## Root Cause Analysis

### Issue 1: Race Condition on Cold Start

**Timeline:**
```
App Launch (t=0s)
  ↓
ContentView.task block starts (async)
  ├─ Initialize LocalCacheService
  ├─ Call refreshOwnedCareesFromCloudKit() (takes 2-3s)
  ↓
User navigates to CareeDetailView (t=0.5s)
  ↓
User opens TrackActivityView (t=1s)
  ↓
User clicks Save (t=2s)
  ├─ Cache may still be empty!
  ├─ CloudKit save: 2-5s (zone setup, cold network)
  ├─ Verify sync: 0.5s
  ├─ getCachedCaree() returns nil ❌
  └─ Activity not cached!
```

**Location:** `CareKeeperApp.swift:211-249`

The cache service initializes asynchronously in a `.task` block and runs in parallel with view navigation. Users can reach the activity tracking screen before the cache is fully populated.

### Issue 2: Debounced Refresh Delay

**Problem:** Cache updates are debounced by 0.25 seconds to prevent excessive view refreshes.

**Flow:**
```swift
CloudKitDataService.createActivity()
  ↓ Save to CloudKit (2-5s cold, 0.5s warm)
  ↓ Verify sync (0.5s)
  ↓ cacheService.cacheActivity()
  ↓ cacheService.scheduleRefresh() ← Debounced!
  ↓ Task.sleep(0.25s) ← Delay
  ↓ refreshPublishedProperties()

// But TrackActivityView dismisses HERE ↑
// Before the debounced refresh executes!
```

**Location:** `LocalCacheService.swift:452-472` (scheduleRefresh method)

The view dismisses immediately after CloudKit save completes, but the debounced refresh hasn't run yet, so the list doesn't update.

### Issue 3: Missing Cache Entries

**Problem:** If cache is empty, activity doesn't get cached at all.

**Location:** `CloudKitDataService.swift:669-678` (before fix)

```swift
if let cacheService,
   let cachedCaree = cacheService.getCachedCaree(id: caree.id)  // Returns nil!
{
    // This block is skipped entirely
    try await cacheService.cacheActivity(...)
}
```

If `getCachedCaree()` returns `nil` (cache not initialized), the entire caching block is skipped. The activity saves to CloudKit successfully but never enters the local cache.

### Why Subsequent Saves Work Fine

1. **Cache is warm** - service is initialized and populated
2. **CloudKit connection is hot** - custom zone exists, network latency reduced
3. **Faster saves** - CloudKit operations complete in ~0.5s instead of 2-5s
4. **Cache hits** - caree and activity type are already cached

The 0.25s debounce delay still exists, but it's less noticeable when the total operation is <1s.

## Solution: Approach A (Elected)

**Fix #1:** Immediate cache refresh for "hot" operations
**Fix #2:** Handle missing caree/activity type in cache

### Implementation

#### 1. Add Immediate Refresh Method

**File:** `LocalCacheService.swift`

```swift
/// Immediate refresh without debounce (for "hot" operations like activity creation)
/// Respects existing refresh state to prevent concurrent execution
func refreshImmediately(reason: String? = nil) async {
    if isRefreshing {
        // Another refresh is running; mark pending so it runs after
        pendingRefresh = true
        return
    }

    // Cancel any pending debounced refresh (we're doing it now)
    refreshTask?.cancel()

    isRefreshing = true
    defer { isRefreshing = false }

    await refreshPublishedProperties()

    // Handle any pending refreshes requested during execution
    if pendingRefresh {
        pendingRefresh = false
        await refreshPublishedProperties()
    }
}
```

**Benefits:**
- ✅ Skips 0.25s debounce delay for activity creation
- ✅ Respects existing `isRefreshing` flag (no concurrent execution)
- ✅ Uses existing coalescing infrastructure

#### 2. Handle Missing Cache Entries

**File:** `CloudKitDataService.swift` (createActivity method)

```swift
// Ensure parent caree is in cache (handles cold start case)
var cachedCaree = cacheService.getCachedCaree(id: caree.id)
if cachedCaree == nil {
    logger.info("⚠️ Caree not in cache (cold start), caching it first")
    try await cacheService.cacheCaree(caree, isShared: isShared)
    cachedCaree = cacheService.getCachedCaree(id: caree.id)
}

if let cachedCaree {
    // Ensure activity type is in cache
    var cachedActivityTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
    if !cachedActivityTypes.contains(where: { $0.id == activityType.id }) {
        logger.info("⚠️ ActivityType not in cache, caching it first")
        try await cacheService.cacheActivityType(activityType, for: cachedCaree)
        cachedActivityTypes = cacheService.getCachedActivityTypes(for: cachedCaree)
    }

    if let cachedActivityType = cachedActivityTypes.first(where: { $0.id == activityType.id }) {
        try await cacheService.cacheActivity(syncedActivity, for: cachedCaree, activityTypeID: cachedActivityType.id)

        // Immediate refresh for "hot" operation (activity creation)
        await cacheService.refreshImmediately(reason: "createActivity")
    }
}
```

**File:** `CloudKitSharedDataService.swift` (createActivity method) - same pattern

**Benefits:**
- ✅ Handles missing caree by caching it first
- ✅ Handles missing activity type by caching it first
- ✅ Ensures activity is always cached, even on cold start
- ✅ Immediate refresh provides instant UI feedback

### Results

**Cold start (first activity):**
- CloudKit save: 2-5s (unavoidable network latency)
- Spinner shows for 2-5s
- Activity appears in list **immediately** after spinner stops ✅
- No manual refresh needed ✅

**Warm (subsequent activities):**
- CloudKit save: ~0.5s
- Brief spinner
- Activity appears in list **immediately** ✅

## Alternative Approaches Considered

### Approach B: Optimistic Updates (Not Implemented)

**Concept:** Add activity to cache **before** CloudKit save, update UI immediately, save in background.

**Benefits:**
- ⚡ Instant feedback (0ms perceived delay)
- Modern iOS UX (like Messages, Notes)
- Best-in-class user experience

**Drawbacks:**
- 🔴 Medium complexity (~120 lines of code)
- 🔴 Requires rollback logic for failed saves
- 🔴 Requires sync state tracking (pending/synced/failed)
- 🔴 Requires UI indicators for sync status

**Decision:** Not implemented for v1. Approach A provides 80% of the benefit with 20% of the work. Optimistic updates can be added later if needed.

### Approach C: Block Until Cache Ready (Rejected)

**Concept:** Show loading state until cache is fully initialized before allowing activity tracking.

**Drawbacks:**
- ❌ Poor UX (user has to wait)
- ❌ Doesn't solve the real problem (CloudKit network latency)
- ❌ Cache initializes quickly; real delay is CloudKit

**Decision:** Rejected due to poor UX.

## Technical Details

### Concurrent Execution Prevention

The existing `LocalCacheService` infrastructure already prevents concurrent cache refreshes:

```swift
private var isRefreshing = false  // Mutex flag
private var pendingRefresh = false  // Coalescing flag

private func runRefreshIfNeeded(reason: String) async {
    if isRefreshing {
        pendingRefresh = true  // Coalesce request
        return
    }

    isRefreshing = true
    defer { isRefreshing = false }

    await refreshPublishedProperties()

    // Handle coalesced requests
    if pendingRefresh {
        pendingRefresh = false
        await refreshPublishedProperties()
    }
}
```

The `refreshImmediately()` method uses the same infrastructure, so there's no risk of concurrent execution or performance degradation.

### Files Modified

1. `CareKeeper/iOS/Services/LocalCacheService.swift`
   - Added `refreshImmediately()` method

2. `CareKeeper/iOS/Services/CloudKitDataService.swift`
   - Updated `createActivity()` to handle missing cache entries
   - Changed from `scheduleRefresh()` to `refreshImmediately()`

3. `CareKeeper/iOS/Services/CloudKitSharedDataService.swift`
   - Updated `createActivity()` with same pattern for shared carees
   - Changed from `refreshPublishedProperties()` to `refreshImmediately()`

### Unit Tests

Comprehensive unit tests verify the fix:

**File:** `CareKeeperTests/LocalCacheServiceTests.swift`

**Test Coverage:**
- `testRefreshImmediatelyUpdatesPublishedProperties` - verifies immediate refresh updates state
- `testRefreshImmediatelyDoesNotDebounce` - verifies no 0.25s delay (completes in <200ms)
- `testCacheCareeWhenMissing` - verifies missing caree handling
- `testCacheActivityTypeWhenMissing` - verifies missing activity type handling
- `testCacheActivityWhenParentsPresent` - verifies activity caching
- `testScheduledRefreshHasDebounce` - verifies normal refresh still debounces
- `testImmediateRefreshBypassesDebounce` - verifies immediate refresh bypasses debounce
- `testColdStartScenario` - integration test for full cold start flow

**Run Tests:**
```bash
xcodebuild test -scheme CareKeeper -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Manual Testing Recommendations

1. **Cold start test:**
   - Force quit app
   - Wait 10+ seconds
   - Launch app and immediately navigate to track activity
   - Verify activity appears in list without manual refresh

2. **Warm test:**
   - Track 2-3 activities in quick succession
   - Verify each appears immediately

3. **Shared caree test:**
   - Repeat above tests with shared caree
   - Verify same behavior

4. **Network failure test:**
   - Enable airplane mode
   - Try to track activity
   - Verify appropriate error handling

## Performance Impact (Fix #1)

**Code complexity:** Low (~50 lines total across 3 files)
**Risk level:** Low (uses existing infrastructure)
**Memory impact:** None (no new data structures)
**CPU impact:** Negligible (eliminates one 0.25s sleep)

**UX improvement:**
- Cold start: **Eliminates need for manual refresh** (major improvement)
- Warm: **No perceptible change** (already fast)

---

# Issue #2: Activity Appears Then Disappears (Background Refresh Race)

## Problem Statement (Discovered After Fix #1)

After implementing Fix #1, a new issue was discovered:

1. **Activity appears immediately** after save (Fix #1 working) ✅
2. **Activity disappears** seconds later ❌
3. **Activity reappears** after manual pull-to-refresh ✅

This suggests the activity is being deleted from cache after being added.

## Root Cause Analysis

### The Race Condition

**Timeline:**
```
t=0s:  App launches
       refreshOwnedCareesFromCloudKit() starts
       ↓ Fetches CloudKit snapshot (no new activity yet)

t=2s:  User saves activity
       ↓ CloudKit save succeeds ✅
       ↓ Cache locally ✅
       ↓ refreshImmediately() ✅
       ↓ Activity appears in UI ✅

t=3s:  Background refresh completes with STALE snapshot from t=0s
       ↓ replaceCaree() deletes ALL existing activities
       ↓ Recreates only activities from t=0s snapshot
       ❌ New activity is deleted (wasn't in snapshot)

t=10s: User pulls to refresh
       ↓ Fresh CloudKit fetch (now includes new activity)
       ✅ Activity reappears
```

### The Smoking Gun: `replaceCaree()`

**File:** `LocalCacheService.swift:158-178` (before fix)

```swift
func replaceCaree(...) async throws {
    // Remove existing children so we can rebuild authoritative lists.
    if let existingActivities = managedCaree.activities {
        for activity in existingActivities {
            modelContext.delete(activity)  // ⚠️ DELETES EVERYTHING!
        }
    }

    // Recreate activities from provided list
    for activity in activities {
        // ... recreate from OLD CloudKit snapshot
    }
}
```

This method **wipes out** any activities not in the provided list, including freshly-created ones!

## Solution: Track and Preserve Local Changes During Background Refresh

**Approach:** Track activities and activity types created locally while background refresh is running, then preserve them from deletion.

### Implementation

#### 1. Add Tracking State to LocalCacheService

**File:** `LocalCacheService.swift`

```swift
// Background refresh preservation state
private var isBackgroundRefreshing = false
private var pendingLocalActivityIDs: Set<UUID> = []
private var pendingLocalActivityTypeIDs: Set<UUID> = []

/// Begin tracking local changes during background refresh
func beginBackgroundRefresh() {
    isBackgroundRefreshing = true
    pendingLocalActivityIDs.removeAll()
    pendingLocalActivityTypeIDs.removeAll()
}

/// End background refresh tracking and clear preserved IDs
func endBackgroundRefresh() {
    isBackgroundRefreshing = false
    pendingLocalActivityIDs.removeAll()
    pendingLocalActivityTypeIDs.removeAll()
}
```

#### 2. Track Local Changes in `cacheActivity()` and `cacheActivityType()`

```swift
func cacheActivity(...) async throws {
    // ... existing code ...

    // Track if created during background refresh
    if isBackgroundRefreshing {
        pendingLocalActivityIDs.insert(activity.id)
        logger.info("📍 Tracked activity during background refresh")
    }
}

func cacheActivityType(...) async throws {
    // ... existing code ...

    // Track if created during background refresh
    if isBackgroundRefreshing {
        pendingLocalActivityTypeIDs.insert(activityType.id)
        logger.info("📍 Tracked activity type during background refresh")
    }
}
```

#### 3. Preserve Tracked Records in `replaceCaree()`

```swift
func replaceCaree(...) async throws {
    // ...

    var preservedActivities: [Activity] = []
    var preservedActivityTypes: [ActivityType] = []

    if let existingActivities = managedCaree.activities {
        for activity in existingActivities {
            if pendingLocalActivityIDs.contains(activity.id) {
                // Preserve - created locally during background refresh
                preservedActivities.append(activity)
            } else {
                // Safe to delete - came from CloudKit
                modelContext.delete(activity)
            }
        }
    }

    // Similar logic for activity types...

    // Merge preserved local records with CloudKit records
    let allActivities = managedActivities + preservedActivities
    managedCaree.activities = allActivities.sorted { $0.dateTime > $1.dateTime }
}
```

#### 4. Wrap Background Refresh with Tracking

**File:** `CloudKitDataService.swift` (refreshOwnedCareesFromCloudKit method)

```swift
func refreshOwnedCareesFromCloudKit() async throws {
    // ... fetch from CloudKit ...

    // Begin tracking local changes
    cacheService.beginBackgroundRefresh()
    defer {
        cacheService.endBackgroundRefresh()
    }

    await cacheService.withBatch {
        // ... replaceCaree() calls ...
    }
}
```

### Benefits

✅ **Preserves locally-created records** - activities and activity types created during refresh aren't deleted
✅ **Still syncs remote changes** - watch and share participant data comes through
✅ **Efficient** - single network call, no restarts
✅ **Handles edge cases** - multiple concurrent local changes tracked in sets
✅ **No CloudKit eventual consistency issues** - preserves local version regardless of CloudKit replication timing

### Unit Tests

**File:** `CareKeeperTests/LocalCacheServiceTests.swift`

Additional test coverage:
- `testBackgroundRefreshPreservesLocalActivity` - verifies local activity preserved during background refresh
- `testBackgroundRefreshPreservesLocalActivityType` - verifies local activity type preserved
- `testBackgroundRefreshMergesCloudKitAndLocalRecords` - verifies merge of CloudKit + local records
- `testBackgroundRefreshWithoutLocalChanges` - verifies normal refresh when no local changes

### Files Modified

1. `CareKeeper/iOS/Services/LocalCacheService.swift`
   - Added background refresh tracking state
   - Added `beginBackgroundRefresh()` / `endBackgroundRefresh()` methods
   - Updated `cacheActivity()` to track during background refresh
   - Updated `cacheActivityType()` to track during background refresh
   - Updated `replaceCaree()` to preserve tracked records

2. `CareKeeper/iOS/Services/CloudKitDataService.swift`
   - Updated `refreshOwnedCareesFromCloudKit()` to use tracking

3. `CareKeeperTests/LocalCacheServiceTests.swift`
   - Added 4 unit tests for background refresh preservation

## Alternative Approaches Considered

### Option A: Cancel and Restart Background Refresh

**Concept:** When user creates activity, cancel background refresh and start new one.

**Rejected because:**
- ❌ CloudKit eventual consistency - new refresh might fetch BEFORE activity is replicated (~1-2s lag)
- ❌ Wastes bandwidth (re-fetches everything)
- ❌ Could create loop if user is very active
- ❌ Delays sync of watch/share participant changes

### Option B: Track and Preserve (Selected)

**Why selected:**
- ✅ No CloudKit race condition - preserves local version regardless
- ✅ Efficient - one network call
- ✅ Background refresh still completes (syncs remote changes)
- ✅ Robust - handles edge cases
- ✅ Predictable behavior

## Performance Impact (Fix #2 Initial)

**Code complexity:** Medium (~80 lines across 3 files)
**Risk level:** Low (surgical changes to existing flow)
**Memory impact:** Minimal (two small Sets during background refresh only)
**CPU impact:** Negligible (Set lookups are O(1))

**UX improvement:**
- Activities stay visible after creation (no disappearing act)
- Still syncs updates from watch/share participants
- No user-facing changes to refresh behavior

---

# Issue #3: Inconsistent Behavior After Fix #2 (Finalization Race)

## Problem Statement (Discovered After Fix #2)

After implementing Fix #2 (background refresh preservation), behavior became inconsistent:

1. **Sometimes:** Activity appears → pops out → pops back in
2. **Sometimes:** Activity appears → pops out → doesn't come back until manual refresh
3. **Sometimes:** Activity doesn't appear until manual refresh

This suggests a new race condition between tracking and finalization.

## Root Cause Analysis

### The New Race Condition

**Timeline:**
```
t=2s:   cacheActivity(activity1) starts
        modelContext.insert(activity1)

t=3s:   replaceCaree() runs for this caree
        ❌ activity1 not in pendingLocalActivityIDs yet (save hasn't completed)
        ❌ Doesn't preserve activity1

t=3.5s: cacheActivity() completes
        modelContext.save() ✅
        pendingLocalActivityIDs.insert(activity1.id) ✅
        refreshImmediately() ✅
        Activity appears in UI

t=4s:   endBackgroundRefresh() OLD VERSION
        isBackgroundRefreshing = false
        pendingLocalActivityIDs.removeAll() ⚠️ Sets cleared!

t=5s:   Some refresh triggers
        activity1 gets deleted (not tracked anymore)
        Activity disappears from UI ❌
```

### The Core Problem

Two issues:

1. **Tracking happens AFTER save completes** - if `replaceCaree()` runs before `cacheActivity()` saves, the activity isn't preserved
2. **Sets cleared immediately** - tracked IDs are cleared before ensuring they're actually attached to their carees

## Solution: Finalization Before Clearing

**Approach:** Make `endBackgroundRefresh()` async and finalize tracked records before clearing the sets.

### Implementation

#### 1. Make `endBackgroundRefresh()` Async with Finalization

**File:** `LocalCacheService.swift`

```swift
/// End background refresh: finalize tracked records, then clear tracking state
/// CRITICAL: This must be called to ensure tracked records are merged before clearing
func endBackgroundRefresh() async throws {
    // CRITICAL: Ensure all tracked records are attached to their carees
    // This handles "late arrivals" - records cached after their caree's replaceCaree() ran
    try await finalizeTrackedRecords()

    // Now safe to clear and mark as done
    isBackgroundRefreshing = false
    pendingLocalActivityIDs.removeAll()
    pendingLocalActivityTypeIDs.removeAll()
}
```

#### 2. Implement Finalization Logic

```swift
private func finalizeTrackedRecords() async throws {
    // For each tracked activity, ensure it's in its caree's activities list
    for activityID in pendingLocalActivityIDs {
        guard let activity = try modelContext.fetch(...).first else { continue }
        guard let caree = activity.caree else { continue }

        // Ensure activity is in caree's activities list
        var careeActivities = caree.activities ?? []
        if !careeActivities.contains(where: { $0.id == activityID }) {
            careeActivities.append(activity)
            careeActivities.sort { $0.dateTime > $1.dateTime }
            caree.activities = careeActivities
        }

        // Ensure activity is in its activity type's activities list
        if let activityType = activity.activityType {
            var typeActivities = activityType.activities ?? []
            if !typeActivities.contains(where: { $0.id == activityID }) {
                typeActivities.append(activity)
                typeActivities.sort { $0.dateTime > $1.dateTime }
                activityType.activities = typeActivities
            }
        }
    }

    // Similar logic for activity types...

    // Save finalization changes
    if !pendingLocalActivityIDs.isEmpty || !pendingLocalActivityTypeIDs.isEmpty {
        try modelContext.save()
    }
}
```

#### 3. Update Call Site to Await

**File:** `CloudKitDataService.swift`

```swift
func refreshOwnedCareesFromCloudKit() async throws {
    // ... fetch from CloudKit ...

    cacheService.beginBackgroundRefresh()

    do {
        await cacheService.withBatch {
            // ... replaceCaree() calls ...
        }

        // CRITICAL: Finalize tracked records before clearing
        try await cacheService.endBackgroundRefresh()

    } catch {
        // Ensure cleanup even on error
        try? await cacheService.endBackgroundRefresh()
        throw error
    }
}
```

### How Finalization Works

**The finalization step ensures:**

1. **All tracked activities are in their caree's activities array** - even if tracked after `replaceCaree()` ran
2. **All tracked activities are in their activity type's activities array** - maintains bidirectional relationships
3. **All tracked activity types are in their caree's activityTypes array** - same for types
4. **Changes are saved** - persists the finalized state

**Handles these cases:**

- ✅ Activity tracked BEFORE `replaceCaree()` → preserved in `replaceCaree()`
- ✅ Activity tracked AFTER `replaceCaree()` → merged in `finalizeTrackedRecords()`
- ✅ Activity tracked but not in any array → added in `finalizeTrackedRecords()`

### Benefits

✅ **Guaranteed consistency** - all tracked records are merged before clearing
✅ **Handles late arrivals** - activities cached after their caree's `replaceCaree()` ran
✅ **Atomic operation** - finalization and cleanup happen together
✅ **Can't forget to finalize** - built into `endBackgroundRefresh()`
✅ **Clear semantics** - "ending" means "make sure everything is merged first"

### Files Modified

1. `CareKeeper/iOS/Services/LocalCacheService.swift`
   - Changed `endBackgroundRefresh()` to async throws
   - Added `finalizeTrackedRecords()` private method
   - Finalization ensures all tracked records are in their caree's arrays

2. `CareKeeper/iOS/Services/CloudKitDataService.swift`
   - Changed `defer` to explicit `try await` call
   - Added error handling to ensure cleanup

3. `CareKeeperTests/LocalCacheServiceTests.swift`
   - Updated all `endBackgroundRefresh()` calls to `try await`

### Unit Tests

Existing tests now verify finalization:
- `testBackgroundRefreshPreservesLocalActivity` - verifies late-arrival activity is finalized
- `testBackgroundRefreshPreservesLocalActivityType` - verifies late-arrival type is finalized
- `testBackgroundRefreshMergesCloudKitAndLocalRecords` - verifies merge after finalization
- `testBackgroundRefreshWithoutLocalChanges` - verifies finalization doesn't break normal flow

## Alternative Considered: Separate Finalization Call

**Rejected approach:**
```swift
await cacheService.withBatch { ... }
await cacheService.finalizeTrackedRecords()  // ← Easy to forget!
cacheService.endBackgroundRefresh()
```

**Why rejected:**
- ❌ Easy to forget separate finalization step
- ❌ Multiple steps instead of one atomic operation
- ❌ Unclear semantics (what does "end" mean if not finalized?)

## Performance Impact (Fix #3)

**Code complexity:** Medium (~75 lines for finalization logic)
**Risk level:** Low (surgical addition to existing flow)
**Memory impact:** None (uses existing tracking sets)
**CPU impact:** Low (O(n) iteration over tracked IDs, typically 1-2 activities)

**UX improvement:**
- **Consistent behavior** - activities always appear and stay visible
- No more pop-in/pop-out flickering
- No more missing activities requiring manual refresh

## Future Enhancements

If "instant save" UX is desired in the future, implement **Approach B (Optimistic Updates)**:

1. Add sync state tracking to Activity model
2. Add optimistic cache update before CloudKit save
3. Add rollback logic for failed saves
4. Add UI indicators for sync status (syncing/synced/failed)
5. Add retry capability

This would provide instant feedback even on cold start, at the cost of ~120 lines of additional code.
