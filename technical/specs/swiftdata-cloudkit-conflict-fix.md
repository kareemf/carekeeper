# Fix: Disable SwiftData CloudKit Sync on Main Container

**Status**: Planned
**Created**: 2026-02-28
**Reviewed by**: Codex (2 iterations — APPROVED)
**Branch**: `fix/creator-notification-identity`

---

## Problem

After commit e772810 ("Fix CloudKit reference actions: .deleteSelf → .none") and running `repairCloudKitReferenceActions()`, reinstalling the app produces:
- Activity counts = 0 on all caree views (incorrect)
- App crashes when navigating to `CareeDetailView`
- Pre-existing carees display correctly (CloudKitDataService + LocalCacheService path works)

---

## Root Cause Analysis

### The Conflict

`sharedModelContainer` (the main SwiftData container) is configured with `cloudKitDatabase: .private(CloudKitConfig.containerID)`. This enables SwiftData's automatic CloudKit import, which runs in the background and processes ALL records in the private database — including records in `com.kareemf.carekeeper.cloudkit.zone` written by our custom `CloudKitDataService`.

SwiftData's internal `PFCloudKitSerializer` has a strict requirement: relationship reference fields (like `CD_caree`) must use `.deleteSelf` action for it to correctly reconstruct record IDs. After commit e772810 changed all references to `.none`, the serializer raises an assertion failure:

```
*** Assertion failure in -[CKRecordID initWithRecordName:zoneID:], CKRecordID.m:44
Record identifier should be a string
```

### Why It's Catastrophic on Fresh Install

On a fresh install there is no CloudKit change token, so SwiftData attempts to import ALL historical records. Every CD_Activity and CD_ActivityType record (329 updated by the repair) triggers the assertion. `NSCloudKitMirroringDelegate` catches repeated failures and resets itself:

```
NSCloudKitMirroringDelegate: Never successfully initialized.
Aborting mirror request: import
```

After this reset, all CloudKit mirroring is permanently broken for the session.

### Secondary Effects

1. **Activity counts = 0**: `CareeDetailView.loadCounts()`, `CareeListRowView.loadCounts()`, and `ActivityTypeRowView` all query `modelContext` (the main SwiftData context). Since the main store failed to import any data, these return 0.
2. **ActivityListView empty**: `loadNextPage()` queries `modelContext` for paginated activities — also returns empty.
3. **SharingView broken**: `@Query myCarees` sources from the empty main context — "Shared by Me" section never populates.
4. **Export broken**: `CareeExportService.exportAllCarees(to:modelContext:)` fetches from `modelContext` — exports 0 carees silently.
5. **App crash**: The background assertion propagates during `CareeDetailView`'s cache refresh cycle.

### Key Architectural Fact

`LocalCacheService` already handles all CloudKit data correctly via our custom fetch code (`CloudKitDataService`, `CloudKitSharedDataService`). The main `sharedModelContainer`'s CloudKit sync is **redundant and conflicting** — it competes with our custom records for the same CloudKit container.

---

## Architectural Analysis

### Why Specs Support This Fix

The **Pure CloudKit Migration Spec** (`technical/specs/pure-cloudkit-migration.md`) independently arrived at the same conclusion:

> "SwiftData's automatic CloudKit sync has unknown timing... No sync completion callback. No way to wait for CloudKit sync. No sync status API. No verification capability."
> "We're already 70% using pure CloudKit (1,420 lines of CloudKit code), so why keep SwiftData's automatic sync?"

The spec explicitly proposes removing `cloudKitDatabase: .private(...)` from the main container. Our fix implements this for the same reasons.

### Is Automatic CloudKit Import Load-Bearing?

**No.** A review of all technical specs confirms that no sync path relies on SwiftData's automatic CloudKit import:

| Sync Path | Actual Mechanism | Uses sharedModelContainer? |
|---|---|---|
| iOS → own devices | CloudKitDataService → LocalCacheService | ❌ No |
| iOS → shared participants | CloudKitDataService → push notifications | ❌ No |
| watchOS → iOS | watchOS writes to CloudKit directly → push notification → CloudKitSharedRecordsService refresh | ❌ No |
| iOS → watchOS | iOS writes to CloudKit directly → SelectiveCloudKitService on watch | ❌ No |

All critical operations already use `LocalCacheService` populated by `CloudKitDataService`. Views that currently use `@Query` or `modelContext` for data display are the only consumers of the automatic import — and they must be updated.

### watchOS Impact

**None.** watchOS does not use SwiftData (per ADR 002 — memory footprint too high). It queries CloudKit directly via `SelectiveCloudKitService` and uses immutable snapshots:

```
CloudKit Records → SelectiveCloudKitService → Snapshots → WatchDataProvider → SwiftUI Views
```

Making `sharedModelContainer` local-only is completely invisible to watchOS in both sync directions:
- **watchOS → iOS**: Watch writes to CloudKit → iOS gets push notification → `CloudKitSharedRecordsService` pulls → `LocalCacheService` updates. `sharedModelContainer` not in path.
- **iOS → watchOS**: iOS writes to CloudKit → Watch `SelectiveCloudKitService` pulls on next refresh. `sharedModelContainer` not in path.

Note: `CD_id` field on watch-created records is still required by `LocalCacheService` (not SwiftData) when reconstructing Activity UUIDs. This is already implemented and unchanged.

---

## Implementation Plan

### Fix 1 — Remove CloudKit sync from `sharedModelContainer`

**File:** `CareKeeper/iOS/App/CareKeeperApp.swift` (lines 57–70)

Remove `cloudKitDatabase: .private(CloudKitConfig.containerID)` from both `ModelConfiguration` branches in `sharedModelContainer`:

```swift
// Before (with group container)
ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    groupContainer: groupContainer,
    cloudKitDatabase: .private(CloudKitConfig.containerID)  // ← REMOVE
)

// Before (without group container)
ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .private(CloudKitConfig.containerID)  // ← REMOVE
)
```

Also update the log message at line 52 from `"Initializing ModelContainer with CloudKit sync"` to `"Initializing ModelContainer (local-only)"`.

**Effect:** No more assertion failures. No more `NSCloudKitMirroringDelegate` resets. Main `modelContext` is local-only and always valid (just empty until Fix 2 redirects views to LocalCacheService).

---

### Fix 2 — Redirect views from modelContext to LocalCacheService

After Fix 1, `modelContext` (from the now-local `sharedModelContainer`) will be empty. Six locations across five views plus one service must be updated. All caree/activity objects in these views already come from LocalCacheService (via EnvironmentObject services), so their SwiftData relationships (`caree.activities`, `caree.activityTypes`, `activityType.activities`) are correctly populated.

#### 2a. CareeDetailView — `loadCounts(for:)`

**File:** `CareKeeper/iOS/Views/Caree/CareeDetailView.swift` (lines 734–744)

```swift
// Before
@MainActor
private func loadCounts(for caree: Caree) async {
    let careeID = caree.id
    do {
        let activityPredicate = #Predicate<Activity> { $0.caree?.id == careeID }
        let typePredicate = #Predicate<ActivityType> { $0.caree?.id == careeID }
        activityCount = try modelContext.fetchCount(FetchDescriptor(predicate: activityPredicate))
        activityTypeCount = try modelContext.fetchCount(FetchDescriptor(predicate: typePredicate))
    } catch { }
}

// After
@MainActor
private func loadCounts(for caree: Caree) async {
    activityCount = caree.activities?.count ?? 0
    activityTypeCount = caree.activityTypes?.count ?? 0
}
```

The `caree` already comes from `resolveCareeFromCache()` → LocalCacheService with populated relationships.

#### 2b. CareeListRowView — `loadCounts()`

**File:** `CareKeeper/iOS/Views/Caree/CareeListRowView.swift` (lines 107–115)

Same pattern. The `caree` is passed from `CareeListView` which sources from LocalCacheService.

```swift
// Before
activityCount = try? modelContext.fetchCount(FetchDescriptor(predicate: activityPredicate))
activityTypeCount = try? modelContext.fetchCount(FetchDescriptor(predicate: typePredicate))

// After
activityCount = caree.activities?.count ?? 0
activityTypeCount = caree.activityTypes?.count ?? 0
```

Remove the now-unused `@Environment(\.modelContext)` if `loadCounts` is its only use.

#### 2c. ActivityTypeRowView — `@Query` replacement

**File:** `CareKeeper/iOS/Views/ActivityType/ActivityTypeRowView.swift` (lines 7–11, ~49)

`@Query private var allActivities: [Activity]` loads ALL activities from the empty main context. The `ActivityType` model already has `totalActivitiesCount: Int { activities?.count ?? 0 }` — use it directly.

```swift
// Before
@Query private var allActivities: [Activity]

private var activitiesCount: Int {
    allActivities.count(where: { $0.activityType?.id == activityType.id })
}
// body: "\(activitiesCount)"

// After — remove @Query and activitiesCount entirely
// body: "\(activityType.totalActivitiesCount)"
```

#### 2d. ActivityListView — `modelContext.fetch` replacement

**File:** `CareKeeper/iOS/Views/Activity/ActivityListView.swift` (lines 6, 43–60, 366–438)

Two uses of `modelContext` must be replaced with in-memory operations on `caree.activities` (already populated from LocalCacheService in `loadInitialPage()`).

**`activities` computed property (lines 43–60):** Order is preserved by using `activityIDs` as the source of truth — the id→activity map + `compactMap` reconstructs in the same order:

```swift
// After
private var activities: [Activity] {
    guard !activityIDs.isEmpty, let caree else { return [] }
    let idSet = Set(activityIDs)
    let idToActivity = Dictionary(
        uniqueKeysWithValues: (caree.activities ?? []).compactMap { a -> (UUID, Activity)? in
            guard idSet.contains(a.id) else { return nil }
            return (a.id, a)
        }
    )
    return activityIDs.compactMap { idToActivity[$0] }
}
```

**`loadNextPage()` (lines 366–438):** Replace predicate build + `modelContext.fetch` with in-memory sort/filter. Sort is deterministic (dateTime DESC, id.uuidString DESC):

```swift
// Replace the predicate build + modelContext.fetch(fetch) block with:
let sorted = (caree.activities ?? []).sorted { lhs, rhs in
    if lhs.dateTime != rhs.dateTime { return lhs.dateTime > rhs.dateTime }
    return lhs.id.uuidString > rhs.id.uuidString
}
let typeFiltered: [Activity] = if let typeID = selectedTypeID {
    sorted.filter { $0.activityType?.id == typeID }
} else { sorted }
let page: [Activity] = if let cursorDate {
    typeFiltered.filter { $0.dateTime <= cursorDate }
} else { typeFiltered }
```

The rest of `loadNextPage()` (deduplication, cursor update, `hasMorePages`) is unchanged.

Remove `@Environment(\.modelContext) private var modelContext` from `ActivityListView`.

#### 2e. SharingView — `@Query` replacement

**File:** `CareKeeper/iOS/Views/Sharing/SharingView.swift` (lines 6–9, ~165–175)

`@Query(sort: \Caree.listOrder) private var myCarees: [Caree]` queries the empty main context.

```swift
// Before
@Environment(\.modelContext) private var modelContext
@Query(sort: \Caree.listOrder) private var myCarees: [Caree]

// After
@EnvironmentObject private var cloudKitService: CloudKitDataService
@State private var myCarees: [Caree] = []
```

Keep `@Environment(\.modelContext)` — needed for `sharingService.canDelete/getShare/stopSharing` call sites. Those methods accept `modelContext` but confirmed unused internally (only `caree.id.uuidString` is used to construct the CloudKit record ID). Passing the empty main context is safe.

Observe both the cacheService becoming available AND its myCarees changes (dual-publisher handles nil-init timing gap):

```swift
// Subscribe to cacheService becoming wired (fires when app init completes)
.onReceive(cloudKitService.$cacheService.compactMap(\.self)) { cache in
    myCarees = cache.myCarees.sorted { $0.listOrder < $1.listOrder }
}
// Subscribe to myCarees changing once cache is available
.onReceive(
    cloudKitService.cacheService?.$myCarees.eraseToAnyPublisher()
        ?? Empty().eraseToAnyPublisher()
) { carees in
    myCarees = carees.sorted { $0.listOrder < $1.listOrder }
}
```

The existing `.onChange(of: myCarees)` modifier still fires correctly since `myCarees` is `@State`.

#### 2f. CareeExportService / CareeListView — export from empty modelContext

**Files:**
- `CareKeeper/iOS/Services/CareeExportService.swift` (line 33)
- `CareKeeper/iOS/Views/Caree/CareeListView.swift` (line 499)

`CareeExportService.exportAllCarees(to:modelContext:)` does `modelContext.fetch(fetchDescriptor)` (line 40). After Fix 1 this silently exports 0 carees.

`CareeListView` already has `@State private var allCarees: [Caree]` populated from LocalCacheService. Fix by replacing the `modelContext`-based method with a `[Caree]`-accepting one:

**CareeExportService** — replace `exportAllCarees(to:modelContext:)` with:
```swift
func exportAllCarees(to url: URL, carees: [Caree]) throws {
    logger.info("Exporting \(carees.count) carees")
    let exportedCarees = carees.map { convertToExportFormat($0) }
    // ... same encoding + write logic as existing method
}
```

Remove the old `(to:modelContext:)` overload entirely — it has no remaining call sites and is a misuse trap.

**CareeListView** call site (line 499):
```swift
// Before
try exportService.exportAllCarees(to: tempURL, modelContext: modelContext)

// After
try exportService.exportAllCarees(to: tempURL, carees: allCarees)
```

---

## Tasks

- [x] Fix 1: Remove `cloudKitDatabase` sync from `sharedModelContainer` (`CareKeeperApp.swift`)
- [x] Fix 2a+2b: Replace `loadCounts` with `caree.activities?.count` in `CareeDetailView` + `CareeListRowView`
- [x] Fix 2c: Replace `@Query allActivities` with `activityType.totalActivitiesCount` in `ActivityTypeRowView`
- [x] Fix 2d: Replace `modelContext.fetch` pagination with in-memory `caree.activities` in `ActivityListView`
- [x] Fix 2e: Replace `@Query myCarees` with dual-publisher `@State` in `SharingView`
- [x] Fix 2f: Replace `exportAllCarees(to:modelContext:)` with `(to:carees:)` in `CareeExportService` + `CareeListView`
- [x] Update `CLAUDE.md` iOS architecture documentation

## Files to Modify

| File | Change |
|---|---|
| `CareKeeper/iOS/App/CareKeeperApp.swift` | Remove `cloudKitDatabase: .private(...)` from `sharedModelContainer`; update log message |
| `CareKeeper/iOS/Views/Caree/CareeDetailView.swift` | `loadCounts` → use `caree.activities?.count` |
| `CareKeeper/iOS/Views/Caree/CareeListRowView.swift` | `loadCounts` → use `caree.activities?.count` |
| `CareKeeper/iOS/Views/ActivityType/ActivityTypeRowView.swift` | Replace `@Query` + filter with `activityType.totalActivitiesCount` |
| `CareKeeper/iOS/Views/Activity/ActivityListView.swift` | Replace `modelContext.fetch` with in-memory `caree.activities` operations |
| `CareKeeper/iOS/Views/Sharing/SharingView.swift` | Replace `@Query myCarees` with `@State` observed via dual `$cacheService`/`$myCarees` publishers |
| `CareKeeper/iOS/Services/CareeExportService.swift` | Replace `exportAllCarees(to:modelContext:)` with `exportAllCarees(to:carees:)` |
| `CareKeeper/iOS/Views/Caree/CareeListView.swift` | Update export call to pass `allCarees` (LocalCacheService state) instead of `modelContext` |
| `CLAUDE.md` | Update iOS architecture section: main container is now local-only, not CloudKit-synced |

## Files NOT Changed

- `CloudKitRecordConverter.swift` — `.none` references are correct; we no longer need SwiftData to accept them
- `CloudKitDataService.swift` — repair code gated by UserDefaults, won't re-run
- `LocalCacheService.swift` — works correctly as-is
- All watchOS targets — use `SelectiveCloudKitService` directly; completely unaffected

---

## Reviewer Notes (Codex, iteration 2 — APPROVED)

- All `modelContext`/`@Query` usages in iOS views are exactly the files listed — no stragglers missed.
- Dual-publisher approach for `SharingView` is correct; harmless duplicate assignments are fine.
- Old `exportAllCarees(to:modelContext:)` should be removed (not kept as deprecated overload) — misuse trap with no remaining call sites.
- Recommend adding/updating tests for: (a) `ActivityListView` in-memory pagination path, (b) `SharingView` cache late-attach behavior.

## Risks / Considerations

- **`SharingView` sharing ops**: Confirmed `CloudKitSharingService.findCKRecord()` uses only `caree.id.uuidString` — passing empty `modelContext` is safe.
- **`ActivityListView` pagination**: In-memory pagination from `caree.activities` is correct when cache is populated. Behavior on empty cache is unchanged from current broken state; pull-to-refresh and cache observers trigger reloads.
- **`CareeListRowView` CloudKitSyncService**: Hits CloudKit directly (not `modelContext`); unaffected.
- **Future SwiftData CloudKit re-enable**: Would require reverting references back to `.deleteSelf` format — addressable if ever needed. Given the Pure CloudKit Migration Spec direction, this is unlikely to be desired.

---

## Verification

1. Build and run on device/simulator (fresh install preferred to reproduce original issue)
2. Caree list loads correctly (correct carees, no duplicates)
3. Caree list rows show correct non-zero activity/type counts
4. Navigate to `CareeDetailView` — app does NOT crash
5. CareeDetailView shows correct non-zero counts
6. `ActivityListView` loads and paginates activities correctly
7. `ActivityTypeRowView` shows correct non-zero activity counts
8. `SharingView` "Shared by Me" section populates correctly
9. Export carees — JSON file contains expected data (not empty)
10. Logs: no `*** Assertion failure in -[CKRecordID initWithRecordName:zoneID:]`
11. Logs: no `NSCloudKitMirroringDelegate resetAfterError`
12. Create a new activity → appears immediately (pending buffer still works)
13. Pull-to-refresh → activities load correctly from CloudKit
14. watchOS: create activity on watch → appears on iOS after refresh (CloudKit path unchanged)
