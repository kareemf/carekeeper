# Pure CloudKit Migration Specification

**Status**: Proposed
**Created**: 2025-10-12
**Author**: Architecture Decision
**Estimated Effort**: 5-7 days

---

## Executive Summary

### Decision
Migrate from SwiftData+CloudKit hybrid approach to Pure CloudKit with SwiftData as local cache.

### Why Now
Current CloudKit sharing implementation is **fundamentally broken**:
- Participants see empty Carees (no image, no ActivityTypes, no Activities)
- SwiftData's automatic sync has unknown timing
- Parent references not set automatically, breaking CloudKit hierarchies
- Binary data (images) don't sync reliably
- No way to verify sync completion before creating shares

### Expected Outcomes
- ✅ Working CloudKit sharing with all data included
- ✅ Deterministic sync behavior
- ✅ Reliable image synchronization
- ✅ Proper parent-child relationships
- ✅ Testable, maintainable architecture
- ✅ Better user experience (sync status, error handling)

### Timeline
- **Phase 1**: Core CloudKit layer (2-3 days)
- **Phase 2**: Local cache service (1-2 days)
- **Phase 3**: View integration (1-2 days)
- **Phase 4**: Migration & testing (1-2 days)
- **Total**: 5-7 days focused work

---

## Problem Analysis

### Where Project Deviates from SwiftData Happy Path

SwiftData + CloudKit integration is designed for:
- ✅ Single-user personal apps (notes, journals)
- ✅ Simple data models (flat hierarchies)
- ✅ Text-based data (minimal binary content)
- ✅ Apps where sync timing doesn't matter
- ✅ Apps without sharing requirements

**CareKeeper's Requirements:**
- ❌ Multi-user collaboration (shared carees between caregivers)
- ❌ CloudKit sharing is core feature (not optional)
- ❌ Complex parent-child relationships (Caree → ActivityTypes/Activities)
- ❌ Binary data is important (profile photos for identification)
- ❌ Need deterministic sync (must verify before sharing)
- ❌ Real-time coordination between users

### Current Architecture Issues

#### Issue 1: CloudKit Sharing Has No SwiftData Support

**Evidence:**
```swift
// Apple's official position
"For advanced sharing scenarios, use CloudKit APIs directly"
```

**Current Workaround:**
- `CloudKitSharingService` - 275 lines of manual CloudKit code
- `CloudKitParentReferenceService` - 214 lines to fix SwiftData limitation
- `CloudKitSharedDataService` - 351 lines for shared record CRUD
- `CloudKitSharedRecordsService` - 410 lines to query shared data

**Result:** Maintaining two competing data layers with impedance mismatch.

#### Issue 2: Unknown Sync Timing

**What SwiftData Provides:**
```swift
modelContext.save() // Local save only
// ❌ No sync completion callback
// ❌ No way to wait for CloudKit sync
// ❌ No sync status API
// ❌ No verification capability
```

**What We Need:**
```swift
try await cloudKit.save(caree)
try await cloudKit.waitForSync()
let verified = try await cloudKit.verify(caree.id)
if verified {
    try await cloudKit.createShare(for: caree)
}
```

**Current Problem:**
1. User creates Caree with ActivityTypes
2. `modelContext.save()` completes immediately (local only)
3. User taps "Share" button
4. `CloudKitSharingService` tries to fix parent references
5. But ActivityTypes haven't synced to CloudKit yet
6. Share created without child records
7. Participant accepts share → sees empty Caree

#### Issue 3: Binary Data Handling

**SwiftData Approach:**
```swift
@Model
class Caree {
    var image: Data?  // How does this become CKAsset? 🤷‍♂️
}
```

**Problems:**
- Documentation unclear on Data → CKAsset conversion
- `@Attribute(.externalStorage)` mentioned but behavior opaque
- No control over upload/download timing
- Participants can't retrieve images reliably

**Pure CloudKit Approach:**
```swift
// Explicit, controllable, testable
let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
try imageData.write(to: tempURL)
let asset = CKAsset(fileURL: tempURL)
record["image"] = asset
try await database.save(record)
```

#### Issue 4: Cascade Relationships Don't Map to CloudKit

**SwiftData Model:**
```swift
@Model
class Caree {
    @Relationship(deleteRule: .cascade)
    var activityTypes: [ActivityType]?
}
```

**What Developers Expect:**
- Cascade should "just work" with CloudKit
- Child records automatically included in shares

**Reality:**
- `deleteRule: .cascade` only affects local deletion
- `CKRecord.parent` is **NOT set automatically**
- Without parent references, CloudKit doesn't include children in shares
- Need manual `CloudKitParentReferenceService` workaround

**Apple's Documentation Gap:**
- No examples of SwiftData relationships + CloudKit sharing
- Parent reference behavior not documented
- Only discoverable through trial and error

### Evidence from Codebase

**CloudKit Code Already Written:**
```
CareKeeper/Services/
├── CloudKitSharingService.swift          (275 lines)
├── CloudKitParentReferenceService.swift  (214 lines)
├── CloudKitSharedDataService.swift       (351 lines)
├── CloudKitSharedRecordsService.swift    (410 lines)
├── CloudKitNotificationService.swift     (119 lines)
└── CloudKitSyncService.swift             (51 lines)
```

**Total:** ~1,420 lines of CloudKit code to work around SwiftData limitations.

**What SwiftData Is Actually Used For:**
- Local storage with `@Model`
- SwiftUI `@Query` for views
- Automatic CloudKit sync (unreliable and opaque)

**Conclusion:** We're already 70% in Pure CloudKit territory, just with extra complexity.

### Apple Documentation Gaps

**What Apple Shows:**
- WWDC 2023: Simple notes app (no sharing, flat model, text-only)
- WWDC 2024: Task manager (no sharing, personal-only)
- CloudKit Sharing Sample: Uses UIDocument + pure CloudKit (no SwiftData)

**What Apple Doesn't Show:**
- ❌ SwiftData + CloudKit sharing together
- ❌ Complex relationships with sharing
- ❌ Binary assets in shared records
- ❌ Multi-user collaboration
- ❌ Sync verification patterns

**Conclusion:** Apple doesn't demonstrate this use case because the integration isn't designed for it.

---

## Proposed Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────┐
│                 SwiftUI Views                       │
│          (@State, @Published, @Environment)         │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│            CloudKitDataService                      │
│          (Single Source of Truth)                   │
│                                                     │
│  • Explicit CRUD operations                        │
│  • Sync verification built-in                      │
│  • Share management                                │
│  • Parent references automatic                     │
│  • Error handling                                  │
└────────────────────┬────────────────────────────────┘
                     │
            ┌────────┴────────┐
            │                 │
┌───────────▼───────┐  ┌─────▼──────────────┐
│   CloudKit        │  │  SwiftData         │
│   (Remote)        │  │  (Local Cache)     │
│                   │  │                    │
│ • Private DB      │  │ • Fast queries     │
│ • Shared DB       │  │ • Offline support  │
│ • Source of truth │  │ • @Query support   │
└───────────────────┘  └────────────────────┘
```

### Data Flow

#### Creating a Caree (Owner)
```
User → SwiftUI → CloudKitDataService.createCaree()
                      ↓
                 Save to CloudKit (with image as CKAsset)
                      ↓
                 Verify save succeeded
                      ↓
                 Cache in SwiftData
                      ↓
                 Return success → Update UI
```

#### Sharing a Caree (Owner)
```
User → SwiftUI → CloudKitDataService.shareCaree()
                      ↓
                 Verify Caree exists in CloudKit
                      ↓
                 Verify ActivityTypes exist (with parent refs)
                      ↓
                 Verify Activities exist (with parent refs)
                      ↓
                 Create CKShare with root record
                      ↓
                 Present UICloudSharingController
                      ↓
                 Update local cache
```

#### Accepting a Share (Participant)
```
User → Share URL → SceneDelegate
                      ↓
                 CloudKitDataService.acceptShare()
                      ↓
                 Query shared zones for Caree + children
                      ↓
                 Download image CKAsset
                      ↓
                 Cache in SwiftData (marked as shared)
                      ↓
                 Navigate to CareeDetailView
```

#### Creating Activity on Shared Caree (Participant)
```
User → TrackActivityView → CloudKitDataService.createActivity()
                                ↓
                           Check if shared caree
                                ↓
                           Save to CloudKit shared DB
                                ↓
                           Set parent reference to Caree
                                ↓
                           Verify save succeeded
                                ↓
                           Cache locally
                                ↓
                           Trigger notification to other participants
```

### Service Layer Architecture

#### CloudKitDataService (New)
**Purpose:** Single source of truth for all data operations

**Responsibilities:**
- CRUD operations for Caree, ActivityType, Activity
- Automatic parent reference management
- CKAsset handling for images
- Sync verification
- Share management integration
- Error handling and retry logic

**Public API:**
```swift
@MainActor
class CloudKitDataService: ObservableObject {
    // Caree operations
    func createCaree(name: String, image: Data?, listOrder: Int) async throws -> Caree
    func updateCaree(_ caree: Caree, name: String?, image: Data?) async throws
    func deleteCaree(_ caree: Caree) async throws
    func fetchCaree(id: UUID) async throws -> Caree?
    func fetchAllCarees() async throws -> [Caree]

    // ActivityType operations
    func createActivityType(for caree: Caree, name: String, ...) async throws -> ActivityType
    func updateActivityType(_ activityType: ActivityType, ...) async throws
    func deleteActivityType(_ activityType: ActivityType) async throws

    // Activity operations
    func createActivity(for caree: Caree, activityType: ActivityType, ...) async throws -> Activity
    func updateActivity(_ activity: Activity, ...) async throws
    func deleteActivity(_ activity: Activity) async throws

    // Share operations
    func shareCaree(_ caree: Caree) async throws -> CKShare
    func stopSharing(_ caree: Caree) async throws
    func acceptShare(metadata: CKShare.Metadata) async throws -> Caree

    // Sync verification
    func verifySynced(_ caree: Caree) async throws -> Bool
    func waitForSync(timeout: TimeInterval) async throws
}
```

#### LocalCacheService (New)
**Purpose:** Manage SwiftData cache of CloudKit data

**Responsibilities:**
- Sync CloudKit records → SwiftData cache
- Handle offline queries
- Provide @Published properties for SwiftUI
- Clear cache on logout
- Mark records as owned vs shared

**Public API:**
```swift
@MainActor
class LocalCacheService: ObservableObject {
    @Published var myCarees: [Caree] = []
    @Published var sharedCarees: [Caree] = []
    @Published var isLoading = false
    @Published var syncError: Error?

    func cacheCaree(_ caree: Caree, isShared: Bool) async throws
    func updateCachedCaree(_ caree: Caree) async throws
    func removeCachedCaree(_ caree: Caree) async throws
    func getCachedCaree(id: UUID) -> Caree?
    func refreshCache() async throws
    func clearCache() async throws
}
```

#### CloudKitRecordConverter (New)
**Purpose:** Bidirectional conversion between domain models and CKRecords

**Responsibilities:**
- Convert Caree/ActivityType/Activity → CKRecord
- Convert CKRecord → Caree/ActivityType/Activity
- Handle CKAsset for images
- Set parent references
- Maintain field naming conventions

**Public API:**
```swift
class CloudKitRecordConverter {
    // To CloudKit
    func careeToRecord(_ caree: Caree, image: Data?) async throws -> CKRecord
    func activityTypeToRecord(_ activityType: ActivityType, parent: CKRecord) throws -> CKRecord
    func activityToRecord(_ activity: Activity, parent: CKRecord) throws -> CKRecord

    // From CloudKit
    func recordToCaree(_ record: CKRecord) async throws -> Caree
    func recordToActivityType(_ record: CKRecord) throws -> ActivityType
    func recordToActivity(_ record: CKRecord) throws -> Activity

    // Asset handling
    func createImageAsset(from data: Data) throws -> CKAsset
    func loadImageData(from asset: CKAsset) async throws -> Data
}
```

### CloudKit Schema

#### CKRecord: CD_Caree
```swift
recordType: "CD_Caree"
recordID: CKRecord.ID("CD_Caree/{UUID}")
zoneID: CKRecordZone.ID("com.apple.coredata.cloudkit.zone")

Fields:
- CD_id: String (UUID)
- CD_name: String
- CD_image: CKAsset (optional)
- CD_listOrder: Int64
- CD_dateCreated: Date

Parent: nil (root record)
```

#### CKRecord: CD_ActivityType
```swift
recordType: "CD_ActivityType"
recordID: CKRecord.ID("CD_ActivityType/{UUID}")
zoneID: CKRecordZone.ID("com.apple.coredata.cloudkit.zone")

Fields:
- CD_id: String (UUID)
- CD_name: String
- CD_icon: String (optional)
- CD_hasQuantity: Int64 (Bool)
- CD_quantityUnit: String (optional)
- CD_hasLocation: Int64 (Bool)
- CD_listOrder: Int64
- CD_dateCreated: Date
- CD_caree: CKRecord.Reference (to CD_Caree)

Parent: CKRecord.Reference (to CD_Caree) ← CRITICAL
```

#### CKRecord: CD_Activity
```swift
recordType: "CD_Activity"
recordID: CKRecord.ID("CD_Activity/{UUID}")
zoneID: CKRecordZone.ID("com.apple.coredata.cloudkit.zone")

Fields:
- CD_id: String (UUID)
- CD_dateTime: Date
- CD_notes: String (optional, encrypted)
- CD_quantity: Double (optional)
- CD_latitude: Double (optional)
- CD_longitude: Double (optional)
- CD_dateCreated: Date
- CD_creatorUserRecordID: String (for notifications)
- CD_caree: CKRecord.Reference (to CD_Caree)
- CD_activityType: CKRecord.Reference (to CD_ActivityType)

Parent: CKRecord.Reference (to CD_Caree) ← CRITICAL
```

### SwiftData Models (Modified)

Keep existing `@Model` classes for local cache, add metadata:

```swift
@Model
final class Caree {
    var id: UUID
    var name: String
    var image: Data?
    var listOrder: Int
    var dateCreated: Date

    // New: Cache metadata
    var isShared: Bool = false
    var isOwned: Bool = true
    var lastSyncedAt: Date?
    var cloudKitRecordID: String?

    @Relationship(deleteRule: .cascade)
    var activityTypes: [ActivityType]?

    @Relationship(deleteRule: .cascade)
    var activities: [Activity]?
}
```

**Key Changes:**
- Add `isShared`, `isOwned` flags for display logic
- Add `lastSyncedAt` for cache invalidation
- Add `cloudKitRecordID` for record tracking
- Keep existing structure otherwise

---

## Implementation Phases

### Phase 1: Core CloudKit Layer (2-3 days)

#### Tasks

**1.1: Create CloudKitRecordConverter**
- [ ] Create `CloudKitRecordConverter.swift`
- [ ] Implement `careeToRecord()` with CKAsset image handling
- [ ] Implement `activityTypeToRecord()` with parent reference
- [ ] Implement `activityToRecord()` with parent reference
- [ ] Implement `recordToCaree()` with CKAsset loading
- [ ] Implement `recordToActivityType()`
- [ ] Implement `recordToActivity()`
- [ ] Add image asset temp file management
- [ ] Add error handling for malformed records
- [ ] Write unit tests with mock records

**1.2: Create CloudKitDataService**
- [ ] Create `CloudKitDataService.swift`
- [ ] Implement Caree CRUD operations
  - [ ] `createCaree()` with image upload
  - [ ] `updateCaree()` with image update
  - [ ] `deleteCaree()` with cascade
  - [ ] `fetchCaree()`
  - [ ] `fetchAllCarees()`
- [ ] Implement ActivityType CRUD operations
  - [ ] `createActivityType()` with parent ref
  - [ ] `updateActivityType()`
  - [ ] `deleteActivityType()`
- [ ] Implement Activity CRUD operations
  - [ ] `createActivity()` with parent ref
  - [ ] `updateActivity()`
  - [ ] `deleteActivity()`
- [ ] Add sync verification methods
  - [ ] `verifySynced()` - check record exists in CloudKit
  - [ ] `waitForSync()` - poll until record found
- [ ] Add comprehensive error handling
- [ ] Add operation retry logic (network failures)
- [ ] Write unit tests with mock CKDatabase

**1.3: Integrate Share Management**
- [ ] Refactor `CloudKitSharingService` to use `CloudKitDataService`
- [ ] Update `shareCaree()` to verify all records before creating share
- [ ] Remove `CloudKitParentReferenceService` (no longer needed)
- [ ] Update share acceptance flow
- [ ] Test end-to-end sharing with verification

**1.4: Update CloudKitSharedDataService**
- [ ] Refactor to use `CloudKitRecordConverter`
- [ ] Use consistent parent reference patterns
- [ ] Add image asset handling for shared records
- [ ] Test CRUD operations on shared records

**Files to Create:**
- `CareKeeper/Services/CloudKitDataService.swift`
- `CareKeeper/Services/CloudKitRecordConverter.swift`

**Files to Modify:**
- `CareKeeper/Services/CloudKitSharingService.swift`
- `CareKeeper/Services/CloudKitSharedDataService.swift`

**Files to Delete:**
- `CareKeeper/Services/CloudKitParentReferenceService.swift` (no longer needed)

---

### Phase 2: Local Cache Service (1-2 days)

#### Tasks

**2.1: Add Cache Metadata to Models**
- [ ] Update `Caree.swift` with cache metadata fields
- [ ] Update `ActivityType.swift` if needed
- [ ] Update `Activity.swift` if needed
- [ ] Create migration for existing SwiftData store
- [ ] Test migration on test data

**2.2: Create LocalCacheService**
- [ ] Create `LocalCacheService.swift`
- [ ] Implement cache write operations
  - [ ] `cacheCaree()` with isShared flag
  - [ ] `updateCachedCaree()`
  - [ ] `removeCachedCaree()`
- [ ] Implement cache read operations
  - [ ] `getCachedCaree()`
  - [ ] `getCachedActivityTypes()`
  - [ ] `getCachedActivities()`
- [ ] Add @Published properties for SwiftUI
  - [ ] `myCarees: [Caree]`
  - [ ] `sharedCarees: [Caree]`
  - [ ] `isLoading: Bool`
  - [ ] `syncError: Error?`
- [ ] Implement cache refresh logic
- [ ] Add cache invalidation (TTL)
- [ ] Add offline detection
- [ ] Write unit tests

**2.3: Integrate Cache with CloudKitDataService**
- [ ] Update `CloudKitDataService` to write to cache after CloudKit operations
- [ ] Add cache fallback for offline scenarios
- [ ] Implement background cache sync
- [ ] Add cache-first read pattern for fast UI
- [ ] Test offline → online transitions

**Files to Create:**
- `CareKeeper/Services/LocalCacheService.swift`

**Files to Modify:**
- `CareKeeper/Models/Caree.swift`
- `CareKeeper/Models/ActivityType.swift`
- `CareKeeper/Models/Activity.swift`
- `CareKeeper/Services/CloudKitDataService.swift`

---

### Phase 3: View Integration (1-2 days)

#### Tasks

**3.1: Update Caree Management Views**
- [ ] Refactor `CareeListView`
  - [ ] Replace `@Query` with `@StateObject var cacheService`
  - [ ] Use `cacheService.myCarees` and `cacheService.sharedCarees`
  - [ ] Add sync status indicator
- [ ] Refactor `CareeEditView`
  - [ ] Replace `modelContext.save()` with `cloudKitService.createCaree()`
  - [ ] Add sync progress indicator
  - [ ] Handle errors with user-facing messages
- [ ] Refactor `CareeDetailView`
  - [ ] Update data source to cache service
  - [ ] Add sync status for shared carees
  - [ ] Show owner vs participant permissions

**3.2: Update Activity Type Management Views**
- [ ] Refactor `ActivityTypeEditView`
  - [ ] Replace save with `cloudKitService.createActivityType()`
  - [ ] Add parent caree reference
  - [ ] Add sync verification before allowing activity creation
- [ ] Update delete operations
  - [ ] Use `cloudKitService.deleteActivityType()`
  - [ ] Show sync progress

**3.3: Update Activity Tracking Views**
- [ ] Refactor `TrackActivityView`
  - [ ] Replace save with `cloudKitService.createActivity()`
  - [ ] Add sync progress indicator
  - [ ] Handle shared vs owned carees
- [ ] Refactor `ActivityListView`
  - [ ] Use cached activities
  - [ ] Show real-time updates from push notifications
- [ ] Refactor `ActivityDetailView`
  - [ ] Use `cloudKitService.updateActivity()`
  - [ ] Handle shared caree permissions

**3.4: Add Sync Status UI Components**
- [ ] Create `SyncStatusView` component
  - [ ] Show syncing/synced/error states
  - [ ] Add manual refresh button
  - [ ] Show last sync time
- [ ] Create `SyncProgressView` for operations
  - [ ] Show progress for uploads
  - [ ] Cancellable operations
- [ ] Add error alerts for sync failures
- [ ] Add offline mode banner

**3.5: Update watchOS Views**
- [ ] Apply same patterns to watchOS views
- [ ] Simplify UI for watch constraints
- [ ] Test sync between iOS ↔ watchOS

**Files to Modify:**
- `CareKeeper/Views/Caree/CareeListView.swift`
- `CareKeeper/Views/Caree/CareeEditView.swift`
- `CareKeeper/Views/Caree/CareeDetailView.swift`
- `CareKeeper/Views/ActivityType/ActivityTypeEditView.swift`
- `CareKeeper/Views/Activity/TrackActivityView.swift`
- `CareKeeper/Views/Activity/ActivityListView.swift`
- `CareKeeper/Views/Activity/ActivityDetailView.swift`
- `CareKeeper Watch App/Views/*.swift`

**Files to Create:**
- `CareKeeper/Views/Components/SyncStatusView.swift`
- `CareKeeper/Views/Components/SyncProgressView.swift`

---

### Phase 4: Migration & Testing (1-2 days)

#### Tasks

**4.1: Data Migration**
- [ ] Create `DataMigrationService`
- [ ] Migrate existing SwiftData records to CloudKit
  - [ ] Export all Carees
  - [ ] For each Caree:
    - [ ] Create CKRecord with image as CKAsset
    - [ ] Create ActivityType CKRecords with parent refs
    - [ ] Create Activity CKRecords with parent refs
    - [ ] Verify all records created
    - [ ] Update local cache with CloudKit IDs
- [ ] Add migration progress UI
- [ ] Add migration error handling
- [ ] Add rollback capability
- [ ] Test migration with various data states

**4.2: Unit Tests**
- [ ] Test `CloudKitRecordConverter`
  - [ ] Caree conversion both directions
  - [ ] ActivityType conversion with parent refs
  - [ ] Activity conversion with parent refs
  - [ ] CKAsset handling
  - [ ] Error cases (malformed records)
- [ ] Test `CloudKitDataService`
  - [ ] CRUD operations (mock CKDatabase)
  - [ ] Sync verification
  - [ ] Parent reference assignment
  - [ ] Error handling and retries
- [ ] Test `LocalCacheService`
  - [ ] Cache write/read operations
  - [ ] Cache invalidation
  - [ ] Offline fallback

**4.3: Integration Tests**
- [ ] Test full create → sync → verify → share flow
- [ ] Test share acceptance → fetch children → cache
- [ ] Test offline → online sync
- [ ] Test conflict resolution
- [ ] Test concurrent edits
- [ ] Test network failure recovery

**4.4: Manual Testing Scenarios**
- [ ] Owner creates Caree with photo → verify in CloudKit Dashboard
- [ ] Owner creates ActivityTypes → verify parent refs
- [ ] Owner shares Caree → participant accepts
- [ ] Participant sees all data (image, ActivityTypes, Activities)
- [ ] Participant creates Activity → owner sees update
- [ ] Test on both iOS and watchOS
- [ ] Test with poor network conditions
- [ ] Test with large images
- [ ] Test with many child records (100+ activities)

**4.5: Performance Testing**
- [ ] Measure save operation times
- [ ] Measure query times (cache vs CloudKit)
- [ ] Test with large datasets
- [ ] Optimize bottlenecks
- [ ] Add caching strategies for images

**Files to Create:**
- `CareKeeper/Services/DataMigrationService.swift`
- `CareKeeperTests/CloudKitRecordConverterTests.swift`
- `CareKeeperTests/CloudKitDataServiceTests.swift`
- `CareKeeperTests/LocalCacheServiceTests.swift`
- `CareKeeperTests/IntegrationTests/`

---

## Migration Strategy

### User Communication

**Before Migration:**
- [ ] Add in-app announcement: "Improved sharing coming soon"
- [ ] Explain data will be migrated to new format
- [ ] Emphasize no data loss
- [ ] Set expectation for one-time sync

**During Migration:**
- [ ] Show progress bar
- [ ] Display: "Upgrading data for improved sharing..."
- [ ] Provide "Learn More" link to docs
- [ ] Allow cancellation (with warning)

**After Migration:**
- [ ] Show success message
- [ ] Highlight new features (reliable sharing)
- [ ] Provide feedback mechanism

### Migration Flow

```
App Launch → Check Migration Status
                  ↓
            [Migration Needed?]
                  ↓
            Show Migration UI
                  ↓
     "Upgrading for Better Sharing"
                  ↓
    [User taps "Start Upgrade"]
                  ↓
    DataMigrationService.migrate()
                  ↓
    ┌─────────────────────────┐
    │ For Each Caree:         │
    │  1. Upload to CloudKit  │
    │  2. Set parent refs     │
    │  3. Upload image asset  │
    │  4. Verify success      │
    │  5. Update cache        │
    └─────────────────────────┘
                  ↓
    [All Carees Migrated?]
                  ↓
    Mark Migration Complete
                  ↓
    Show Success → Continue to App
```

### Rollback Plan

If migration fails critically:

1. **Preserve Original Data**
   - Keep SwiftData store intact during migration
   - Only mark as migrated after verification
   - Allow rollback to previous version

2. **Version Detection**
   ```swift
   let migrationVersion = UserDefaults.standard.integer(forKey: "dataVersion")
   if migrationVersion < 2 {
       // Use old SwiftData approach
   } else {
       // Use new Pure CloudKit approach
   }
   ```

3. **Rollback Procedure**
   - If user downgrades app version
   - Detect old version
   - Disable CloudKit operations
   - Fall back to SwiftData-only mode
   - Show warning about sharing unavailable

### Backwards Compatibility

**During Transition Period (1-2 weeks):**
- Support both old and new data formats
- Detect which format user has
- Migrate on first launch of new version
- Keep old code path for rollback

**After Transition:**
- Remove old SwiftData CloudKit sync code
- Remove compatibility shims
- Clean up migration code

---

## Testing Plan

### Unit Test Coverage

**Required Tests:**

**CloudKitRecordConverter:**
- ✅ Convert Caree to CKRecord with image
- ✅ Convert CKRecord to Caree with image asset
- ✅ Convert ActivityType with parent reference
- ✅ Convert Activity with all optional fields
- ✅ Handle missing optional fields gracefully
- ✅ Error handling for malformed data

**CloudKitDataService:**
- ✅ Create Caree saves to CloudKit
- ✅ Create Caree with large image (>10MB)
- ✅ Update Caree preserves relationships
- ✅ Delete Caree cascades to children
- ✅ Create ActivityType sets parent reference
- ✅ Create Activity on shared caree uses shared DB
- ✅ Sync verification polling with timeout
- ✅ Retry logic on network failure
- ✅ Error handling for CloudKit errors

**LocalCacheService:**
- ✅ Cache write populates SwiftData
- ✅ Cache read returns correct data
- ✅ Cache invalidation after TTL
- ✅ Offline mode returns cached data
- ✅ Cache refresh merges updates
- ✅ Clear cache removes all records

### Integration Tests

**End-to-End Flows:**
1. ✅ Create → Verify → Share → Accept flow
2. ✅ Participant CRUD on shared Caree
3. ✅ Offline creation → Online sync
4. ✅ Concurrent edits → Conflict resolution
5. ✅ Migration from old format → New format

### Manual Test Scenarios

**Critical Paths:**

**Scenario 1: Basic Sharing**
1. Owner creates Caree "Baby Emma" with photo
2. Owner adds ActivityType "Feeding"
3. Owner adds Activity "Fed 4oz at 3pm"
4. Owner taps Share → sends link via Messages
5. Participant accepts share
6. **Verify:** Participant sees photo, ActivityType, Activity

**Scenario 2: Participant CRUD**
1. Participant opens shared Caree
2. Participant adds ActivityType "Nap Time"
3. Participant tracks "Napped 2 hours"
4. **Verify:** Owner sees new ActivityType and Activity
5. **Verify:** Push notification sent to owner

**Scenario 3: Large Image**
1. Owner selects 20MB photo
2. App uploads to CloudKit
3. Owner shares Caree
4. **Verify:** Participant can download image
5. **Verify:** Image displayed correctly

**Scenario 4: Offline → Online**
1. Owner turns on airplane mode
2. Owner creates Activity
3. **Verify:** Activity saved to cache
4. **Verify:** UI shows "Pending sync"
5. Owner turns off airplane mode
6. **Verify:** Activity syncs to CloudKit
7. **Verify:** Participant receives update

**Scenario 5: Poor Network**
1. Owner enables Network Link Conditioner (3G, 100ms latency, 5% packet loss)
2. Owner creates Caree with image
3. **Verify:** Operation completes with retries
4. **Verify:** User sees progress indicator
5. **Verify:** Error handling if timeout

### Performance Requirements

**Benchmarks:**
- Create Caree with image: < 3 seconds
- Fetch all Carees (cached): < 100ms
- Fetch all Carees (remote): < 2 seconds
- Create Activity: < 1 second
- Share creation: < 2 seconds
- Share acceptance: < 5 seconds
- Cache refresh: < 1 second

**Scalability:**
- Support 50+ Carees per user
- Support 1000+ Activities per Caree
- Handle 10MB+ images
- Support 10+ participants per share

---

## Success Criteria

### Functional Requirements

**Must Have (Blocking):**
- ✅ Owner can share Caree with all data (image, ActivityTypes, Activities)
- ✅ Participant sees all shared data immediately after accepting
- ✅ Participant can create/edit/delete ActivityTypes and Activities
- ✅ Owner receives push notifications for participant changes
- ✅ Images sync reliably via CKAsset
- ✅ Offline mode works (cache fallback)
- ✅ Data migration from old format succeeds
- ✅ No data loss during migration

**Should Have (Important):**
- ✅ Sync status visible to users
- ✅ Network error handling with retries
- ✅ Conflict resolution for concurrent edits
- ✅ Performance meets benchmarks
- ✅ watchOS feature parity maintained

**Nice to Have (Future):**
- ⚠️ Background sync optimization
- ⚠️ Prefetching for faster UX
- ⚠️ Batch operations for bulk updates
- ⚠️ Advanced conflict resolution UI

### Non-Functional Requirements

**Reliability:**
- 99% success rate for sync operations
- 0% data loss rate
- < 1% crash rate
- Graceful degradation on network issues

**Performance:**
- All operations meet benchmark times
- UI remains responsive during sync
- Memory usage < 100MB for typical workload
- Battery impact < 5% per hour of active use

**Maintainability:**
- Unit test coverage > 80%
- Integration test coverage for critical paths
- Clear separation of concerns
- Well-documented public APIs
- Follows Swift best practices

**User Experience:**
- Clear sync status indicators
- Helpful error messages
- No blocking operations (async/await)
- Progress feedback for long operations
- Offline mode seamless

---

## Risk Assessment

### High Risk

**1. Data Migration Complexity**
- **Risk:** Existing user data fails to migrate
- **Mitigation:**
  - Comprehensive testing with various data states
  - Rollback capability
  - Keep old data intact during migration
  - Phased rollout with monitoring

**2. Breaking Changes for Users**
- **Risk:** Users lose access to data temporarily
- **Mitigation:**
  - Thorough testing before release
  - Beta testing with real users
  - Clear communication about upgrade
  - Support for rollback

### Medium Risk

**3. Performance Degradation**
- **Risk:** Pure CloudKit is slower than expected
- **Mitigation:**
  - Cache-first read strategy
  - Background sync
  - Image size optimization
  - Batch operations

**4. CloudKit Quota Limits**
- **Risk:** Hit CloudKit API rate limits
- **Mitigation:**
  - Implement exponential backoff
  - Batch operations where possible
  - Monitor usage patterns
  - Optimize query patterns

### Low Risk

**5. Learning Curve for Team**
- **Risk:** Pure CloudKit patterns unfamiliar
- **Mitigation:**
  - Comprehensive documentation
  - Code examples
  - Pair programming
  - Code review process

---

## Timeline & Resources

### Estimated Timeline

**Week 1:**
- Days 1-2: Phase 1 (Core CloudKit Layer) - Part 1
- Day 3: Phase 1 (Core CloudKit Layer) - Part 2
- Days 4-5: Phase 2 (Local Cache Service)

**Week 2:**
- Days 1-2: Phase 3 (View Integration)
- Days 3-4: Phase 4 (Migration & Testing)
- Day 5: Buffer for issues + documentation

**Total: 8-10 days**

### Development Resources

**Required:**
- 1 Senior iOS Developer (full-time)
- Access to CloudKit Dashboard
- Test devices (iOS + watchOS)
- Test iCloud accounts (multiple for sharing)

**Optional:**
- QA Engineer for manual testing
- Designer for sync status UI

### Dependencies

**External:**
- CloudKit service availability
- Apple Developer account
- TestFlight for beta testing

**Internal:**
- No other features in flight during migration
- Code freeze on data layer during development
- Team availability for testing

---

## Appendix

### References

**Apple Documentation:**
- [CloudKit Quick Start](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/)
- [CloudKit Sharing](https://developer.apple.com/documentation/cloudkit/shared_records)
- [CKRecord Parent References](https://developer.apple.com/documentation/cloudkit/ckrecord/1462210-parent)
- [CKAsset](https://developer.apple.com/documentation/cloudkit/ckasset)

**Sample Code:**
- [CloudKit Samples](https://developer.apple.com/documentation/cloudkit/samples)
- [Synchronizing Data with CloudKit](https://developer.apple.com/documentation/coredata/mirroring_a_core_data_store_with_cloudkit)

### Glossary

- **CKRecord:** CloudKit's fundamental data object, like a database row
- **CKAsset:** CloudKit's binary data type for files (images, documents)
- **CKShare:** CloudKit's sharing object that defines permissions
- **CKRecordZone:** Grouping of records, created per share
- **Parent Reference:** `CKRecord.parent` that creates hierarchy for sharing
- **Private Database:** User's personal CloudKit database
- **Shared Database:** CloudKit database containing accepted shares

### Decision Log

**2025-10-12: Decision to Migrate to Pure CloudKit**
- **Context:** Current sharing implementation broken due to SwiftData+CloudKit impedance mismatch
- **Decision:** Migrate to Pure CloudKit with SwiftData as local cache
- **Rationale:** Already 70% using CloudKit, sharing requires explicit control, need deterministic sync
- **Alternatives Considered:**
  1. Fix SwiftData approach (deemed insufficient)
  2. Remove sharing feature (doesn't meet product goals)
- **Stakeholders:** Development team, users (via reliable sharing)
- **Status:** Approved, implementation pending

---

**End of Specification**

*This document will be updated as implementation progresses.*
