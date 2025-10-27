# WatchOS Stability Refactor Plan

**Created**: 2025-10-25
**Status**: In Progress
**Goal**: Achieve stable watchOS app through selective CloudKit queries and defensive programming

---

## Core Strategy: Selective CloudKit Queries + Defensive Programming

Based on Apple's official guidance (WWDC 2021 - "There and back again: Data transfer on Apple Watch"), the stability issues are caused by **data volume and complexity**, not the choice of CloudKit vs WatchConnectivity.

### Apple's Guidance
> "You can quickly get too much data on a Watch. CloudKit syncing ~10k entities may never complete on watch. Think carefully about what information customers really need."

**Recommendation**: Independent watchOS apps should use direct CloudKit access (not WatchConnectivity relay), but with **selective queries and aggressive filtering**.

---

## Root Cause Hypothesis

### Current Problems:
1. ❌ **Over-fetching data**: Loading all activities for all carees into memory
2. ❌ **Eager relationship loading**: `caree.activityTypes?.count` triggers full relationship fetch
3. ❌ **No data limits**: Activity history could be thousands of records
4. ❌ **Complex reactive chains**: 6+ Combine subscriptions in CareeListView
5. ❌ **Missing task cancellation**: Tasks continue after views disappear
6. ❌ **Memory pressure**: Too much data for watchOS constraints

### Solution Strategy:
- ✅ **Selective queries**: Load only recent data (last 48 hours)
- ✅ **Hard limits**: Cap at 100 activities per query
- ✅ **Lazy loading**: Load activity types/activities on-demand, not upfront
- ✅ **Immutable snapshots**: No SwiftData relationships in views
- ✅ **Task cancellation**: Cancel all async work when views disappear
- ✅ **Memory management**: Clear cache when not in use

---

## Implementation Phases

### ✅ Phase 0: Diagnostics & Baseline (1-2 days) - START HERE

**Goal**: Confirm hypothesis before refactoring

**Tasks**:
1. Add MetricKit integration for crash reports from TestFlight
2. Add memory monitoring to track usage patterns
3. Add query result size logging to identify over-fetching
4. Create diagnostic view on iPhone to read watch logs
5. Run baseline test on physical device

**Deliverables**:
- MetricsManager.swift - Captures crash/hang diagnostics
- MemoryMonitor.swift - Logs memory usage at checkpoints
- WatchDiagnosticsView.swift (iOS) - Read watch logs from app group
- Baseline metrics document

**Expected Findings**:
- Memory spike when loading all activities
- Crash when accessing `caree.activityTypes` on shared carees
- Slow/hanging UI with large datasets

---

### Phase 1: Selective CloudKit Queries ⭐ (2-3 days)

**Goal**: Fetch only what's needed, when it's needed

**Strategy**: Lazy, Filtered, Paginated

**Key Constants**:
```swift
static let activityHistoryHours: TimeInterval = 48 * 3600  // 48 hours
static let maxActivitiesPerCaree = 100
static let maxActivityTypes = 50
```

**Tasks**:
1. Create `SelectiveCloudKitService.swift`
   - `fetchAllCarees()` - Load all carees (acceptable, small dataset)
   - `fetchActivityTypes(for:isShared:)` - On-demand per caree
   - `fetchRecentActivities(for:hoursBack:)` - Time-filtered + limited
   - `fetchActivityTypeCount(for:)` - Lightweight count query

2. Create snapshot models (immutable value types):
   - `CareeSnapshot` - No relationships, pre-loaded count
   - `ActivityTypeSnapshot` - Standalone, no caree relationship
   - `ActivitySnapshot` - No relationships, includes sync state

3. Create `WatchDataProvider.swift`
   - Manages snapshot state with @Published
   - Loads carees eagerly (small)
   - Loads activity types lazily (on caree tap)
   - Loads activities lazily (on list open)
   - `clearUnusedCache()` for memory management

**Deliverables**:
- SelectiveCloudKitService.swift
- Snapshots.swift (CareeSnapshot, ActivityTypeSnapshot, ActivitySnapshot)
- WatchDataProvider.swift

---

### Phase 2: Defensive Programming Patterns (1-2 days)

**Goal**: Prevent crashes from async/UI race conditions

**Tasks**:
1. Add task cancellation guards to all views
   ```swift
   @State private var loadTask: Task<Void, Never>?

   .task {
       loadTask?.cancel()
       loadTask = Task { await load() }
   }
   .onDisappear {
       loadTask?.cancel()
   }
   ```

2. Add cancellation checks in async functions
   ```swift
   guard !Task.isCancelled else { return }
   ```

3. Use immutable snapshots in all views (no SwiftData models)

4. Add memory cleanup on view disappear

**Deliverables**:
- Updated all watch views with defensive patterns
- No SwiftData model access in view layer

---

### Phase 3: View Layer Rebuild (1-2 days)

**Goal**: Lazy loading UI with graceful states

**Views to Update**:

1. **CareeListView**
   - Load carees on appear
   - Show loading/error/empty states
   - Pass snapshots to rows (not models)
   - Task cancellation on disappear

2. **CareeDetailView**
   - Lazy load activity types when view appears
   - Clear cache when disappears
   - Task cancellation guards

3. **ActivityListView**
   - Lazy load recent activities (48h default)
   - Pagination: "Load Older" button for more history
   - Task cancellation

4. **TrackActivityView**
   - Work with snapshots
   - Optimistic UI (show pending state)

**Deliverables**:
- Refactored CareeListView.swift
- Refactored CareeDetailView.swift
- Refactored ActivityListView.swift
- Refactored TrackActivityView.swift

---

### Phase 4: Testing & Validation (2-3 days)

**Goal**: Verify stability under real-world conditions

**Tests**:

1. **Unit Tests**
   - Test selective query limits
   - Test lazy loading behavior
   - Test snapshot creation

2. **Stress Testing**
   - Seed large dataset (10 carees, 20 types each, 1000 activities each)
   - Verify memory stays under 30MB
   - Verify UI remains responsive

3. **Network Condition Testing**
   - Offline mode (cached data)
   - Poor connectivity (retries)
   - Slow network (no UI blocking)

4. **Device Testing**
   - Physical watch with TestFlight
   - Collect MetricKit diagnostics
   - Monitor for crashes

**Success Criteria**:
- ✅ App launches and loads carees in <2s
- ✅ Memory usage stays under 30MB even with large dataset
- ✅ No crashes after 10 minutes of continuous use
- ✅ Can navigate all views without hanging
- ✅ Can track activity successfully
- ✅ Works offline with cached data
- ✅ Handles poor network gracefully

**Deliverables**:
- Unit test suite (SelectiveCloudKitServiceTests.swift)
- Stress test results document
- TestFlight validation report

---

## What Makes This Stable

| Problem | Solution |
|---------|----------|
| Over-fetching data | Selective queries with hard limits (100 activities max) |
| Eager loading | Lazy loading (activity types on caree tap, activities on list open) |
| Unlimited history | Time-based filter (last 48h) + pagination |
| Unsafe relationships | Immutable snapshots (no SwiftData relationships in UI) |
| Missing cancellation | Task cancellation guards on all async operations |
| Complex Combine | Explicit async/await, minimal publishers |
| Memory pressure | Cache clearing on view disappear |
| No diagnostics | MetricKit + memory monitoring |

---

## Key Architectural Decisions

### ✅ Direct CloudKit (Not WatchConnectivity Relay)

**Reasoning**:
- Apple explicitly states: "WatchConnectivity is not recommended if you want your watch app to be standalone"
- Independent watch app needs to work without iPhone proximity
- CloudKit sharing requires CloudKit infrastructure anyway
- Data shared across multiple users (not just iPhone-Watch pair)

**Trade-off**: Higher battery usage than WC, but enables standalone functionality

### ✅ Selective Queries (Not Full Dataset Sync)

**Reasoning**:
- Apple warns: "~10k entities may never complete syncing on watch"
- Watch users only need recent data (last 48 hours typical)
- Pagination available for older history if needed
- Dramatically reduces memory footprint

**Trade-off**: Can't see full activity history without pagination

### ✅ Immutable Snapshots (Not SwiftData Models in UI)

**Reasoning**:
- SwiftData relationships can trigger cascade fetches
- Accessing invalidated models causes crashes
- Value types are thread-safe and crash-proof
- Simpler state management

**Trade-off**: Extra layer of model conversion

---

## Implementation Timeline

| Phase | Duration | Start | End | Status |
|-------|----------|-------|-----|--------|
| Phase 0: Diagnostics | 1-2 days | TBD | TBD | Not Started |
| Phase 1: Selective Queries | 2-3 days | TBD | TBD | Not Started |
| Phase 2: Defensive Patterns | 1-2 days | TBD | TBD | Not Started |
| Phase 3: View Rebuild | 1-2 days | TBD | TBD | Not Started |
| Phase 4: Testing | 2-3 days | TBD | TBD | Not Started |
| **Total** | **8-12 days** | | | |

---

## Progress Tracking

### Phase 0: Diagnostics ⏳
- [ ] Create MetricsManager.swift
- [ ] Create MemoryMonitor.swift
- [ ] Add query result logging to CloudKitDataService
- [ ] Create WatchDiagnosticsView.swift (iOS)
- [ ] Run baseline test on device
- [ ] Document findings

### Phase 1: Selective Queries ⏳
- [ ] Create SelectiveCloudKitService.swift
- [ ] Create Snapshots.swift (CareeSnapshot, ActivityTypeSnapshot, ActivitySnapshot)
- [ ] Create WatchDataProvider.swift
- [ ] Unit tests for selective queries
- [ ] Verify memory improvements

### Phase 2: Defensive Patterns ⏳
- [ ] Add task cancellation to CareeListView
- [ ] Add task cancellation to CareeDetailView
- [ ] Add task cancellation to ActivityListView
- [ ] Remove all SwiftData model access from views
- [ ] Add memory cleanup on view disappear

### Phase 3: View Rebuild ⏳
- [ ] Refactor CareeListView
- [ ] Refactor CareeDetailView
- [ ] Refactor ActivityListView
- [ ] Refactor TrackActivityView
- [ ] Update ActivityDetailView
- [ ] Test all navigation flows

### Phase 4: Testing ⏳
- [ ] Write unit tests
- [ ] Create stress test dataset
- [ ] Test with Network Link Conditioner
- [ ] Deploy to TestFlight
- [ ] Collect MetricKit diagnostics
- [ ] Validate success criteria
- [ ] Document final results

---

## File Structure

```
CareKeeper Watch App/
├── Services/
│   ├── SelectiveCloudKitService.swift      [NEW - Phase 1]
│   ├── WatchDataProvider.swift             [NEW - Phase 1]
│   ├── MetricsManager.swift                [NEW - Phase 0]
│   └── MemoryMonitor.swift                 [NEW - Phase 0]
├── Models/
│   └── Snapshots.swift                     [NEW - Phase 1]
├── Views/
│   ├── CareeListView.swift                 [REFACTOR - Phase 3]
│   ├── CareeDetailView.swift               [REFACTOR - Phase 3]
│   ├── ActivityListView.swift              [REFACTOR - Phase 3]
│   ├── TrackActivityView.swift             [REFACTOR - Phase 3]
│   └── ActivityDetailView.swift            [UPDATE - Phase 3]
└── Tests/
    └── SelectiveCloudKitServiceTests.swift [NEW - Phase 4]

CareKeeper/ (iOS)
└── Views/
    └── Debug/
        └── WatchDiagnosticsView.swift      [NEW - Phase 0]
```

---

## Notes & Decisions

### Why Not WatchConnectivity?
- Apple's guidance is clear: use direct CloudKit for independent apps
- WatchConnectivity adds complexity without solving root cause
- Can add later as optimization if needed (for instant updates when phone nearby)

### Why Snapshots Instead of SwiftData?
- SwiftData relationships are crash-prone on watch
- Immutable value types prevent invalid model access
- Simpler debugging and testing
- Better performance (no fetch cascades)

### Why 48 Hours Default?
- Covers typical caregiver use case (recent activity tracking)
- Small enough to load quickly
- Pagination available for older history
- Can adjust based on user feedback

### Memory Budget
- Target: <30MB resident memory
- Current problem: Likely >50MB with full dataset
- Selective queries should reduce to ~10-15MB

---

## Rollback Plan

If refactor doesn't improve stability:
1. Use diagnostics to identify exact failure point
2. Consider WatchConnectivity as fallback
3. Reduce feature set (view-only, no create/edit)
4. Document findings for future investigation

---

## Success Metrics

### Before Refactor (Baseline)
- [ ] Crash rate: TBD (from MetricKit)
- [ ] Memory usage: TBD (from monitoring)
- [ ] Time to load carees: TBD
- [ ] Data fetched per launch: TBD

### After Refactor (Target)
- [ ] Crash rate: <1% of sessions
- [ ] Memory usage: <30MB peak
- [ ] Time to load carees: <2s
- [ ] Data fetched: Only last 48h activities (~100 max)

---

## References

- [Apple WWDC 2021: Data transfer on Apple Watch](https://developer.apple.com/videos/play/wwdc2021/10003/)
- [Energy Efficiency Guide: Apple Watch Best Practices](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/AppleWatchExtensionBestPractices.html)
- [Watch Connectivity Documentation](https://developer.apple.com/documentation/watchconnectivity)
- [MetricKit Documentation](https://developer.apple.com/documentation/metrickit)
