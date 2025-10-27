# ADR 005: Snapshot Pattern for watchOS Data Models

## Status
Accepted

## Context
watchOS uses direct CloudKit without SwiftData (see ADR 002). However, we still need value types for:
- Passing data between views
- Optimistic UI updates (show changes immediately, sync in background)
- Preventing accidental relationship traversal
- Memory safety (no retain cycles)

SwiftData models (Caree, ActivityType, Activity) are classes with `@Relationship` properties that could trigger expensive fetches. watchOS needs **immutable, flat data structures**.

## Decision
Create **snapshot structs** mirroring the SwiftData models:

```swift
struct CareeSnapshot: Identifiable {
    let id: UUID
    let name: String
    let image: Data?
    let listOrder: Int
    let dateCreated: Date
    let isShared: Bool
    let isOwned: Bool
}

struct ActivityTypeSnapshot: Identifiable {
    let id: UUID
    let name: String
    let icon: String?
    let hasQuantity: Bool
    let quantityUnit: String?
    let hasLocation: Bool
    let listOrder: Int
    let careeId: UUID  // Flat - no relationship
}

struct ActivitySnapshot: Identifiable {
    let id: UUID
    let dateTime: Date
    let notes: String?
    let quantity: Double?
    let latitude: Double?
    let longitude: Double?
    let activityTypeId: UUID  // Flat - no relationship
    let careeId: UUID          // Flat - no relationship
}
```

All watchOS views use snapshots, not SwiftData models.

## Consequences

### Positive
- **Immutable**: Snapshots are `let` constants, thread-safe by default
- **Flat structure**: No relationships = no accidental fetches
- **Predictable memory**: Known size, no hidden object graphs
- **Value semantics**: Pass by value, no retain cycles
- **Optimistic UI**: Easy to create modified snapshots before sync
- **Testable**: Simple struct initialization, no SwiftData context needed

### Negative
- **Code duplication**: Snapshot structs duplicate SwiftData model structure
- **Manual conversion**: Must convert CloudKit → Snapshot in SelectiveCloudKitService
- **Type mismatch**: iOS uses SwiftData models, watchOS uses snapshots
- **Join operations**: Must manually look up related objects by ID
- **Sync complexity**: No automatic updates, must manually replace snapshots

### Implementation Pattern

**Loading snapshots:**
```swift
// WatchDataProvider.loadActivityTypes()
let records = try await service.fetchActivityTypes(for: careeID)
let snapshots = records.map { ActivityTypeSnapshot(from: $0) }
activityTypeCache[careeID] = snapshots
```

**Optimistic updates:**
```swift
// WatchDataProvider.saveActivity()
let pendingSnapshot = ActivitySnapshot(
    id: UUID(),
    dateTime: Date(),
    notes: "New activity",
    // ... other fields
)

// Show immediately in UI
activityCache[careeID] = [pendingSnapshot] + (activityCache[careeID] ?? [])

// Sync in background
Task.detached {
    try await service.createActivity(pendingSnapshot, careeId: careeID)
    // Update cache with synced version
}
```

**Looking up related objects:**
```swift
// ActivityListView
let activityType = watchDataProvider.activityTypeCache[careeId]?
    .first { $0.id == activity.activityTypeId }
```

## Alternatives Considered
1. **Use SwiftData models on watchOS**:
   - ❌ Requires ModelContainer (memory overhead)
   - ❌ Risk of relationship traversal (memory spikes)
   - ❌ See ADR 002 for why this was rejected

2. **Use CloudKit records directly in views**:
   - ❌ Verbose field access: `record["CD_name"] as? String ?? ""`
   - ❌ Optional handling for every field
   - ❌ Not type-safe

3. **Generate snapshots from SwiftData models**:
   - ❌ Still requires SwiftData on watchOS
   - ❌ Conversion overhead
   - ❌ Doesn't solve memory problem

## Future Consideration
Could adopt snapshots for iOS views as well:
- Consistent data model across platforms
- Better testability (no SwiftData context in tests)
- Clearer separation between persistence and UI
- Trade-off: Lose SwiftData automatic view updates via `@Query`

## Related
- ADR 002: Direct CloudKit for watchOS (why we need snapshots)
- WatchDataProvider implementation
- SelectiveCloudKitService CloudKit → Snapshot conversion
