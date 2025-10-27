# ADR 004: Manual Cascade Deletion for CloudKit Records

## Status
Accepted

## Context
CloudKit sharing requires specific parent reference behavior. When setting up the sharing hierarchy (Caree → ActivityType → Activity), CloudKit constrains how parent references work:

- Parent references in shared hierarchies **must** use `CKRecord.ReferenceAction.none`
- Cannot use `.deleteSelf` (automatic cascade deletion)
- This is a CloudKit platform requirement, not a design choice

Without proper cascade deletion, deleting a Caree would leave orphaned ActivityType and Activity records.

## Decision
Implement **manual cascade deletion** in CloudKitDataService.deleteCaree():

```swift
// Order is critical:
1. Query all ActivityTypes for the Caree
2. For each ActivityType, query and delete all Activities
3. Delete all ActivityTypes
4. Finally delete the Caree record
```

Include progress tracking (0.0 to 1.0) and display progress indicator in UI:
- 0.0-0.2: Querying ActivityTypes
- 0.2-0.6: Deleting Activities
- 0.6-0.8: Deleting ActivityTypes
- 0.8-0.9: Deleting Caree
- 0.9-1.0: Cache cleanup

## Consequences

### Positive
- **Complies with CloudKit**: Uses `.none` as required for sharing
- **No orphaned records**: Explicit deletion ensures clean removal
- **Progress feedback**: Users see real-time progress for long operations
- **Retry capability**: Can retry individual steps on failure
- **Explicit control**: Developer understands exactly what's deleted

### Negative
- **Slower deletion**: Network round-trips for queries and batch deletes
- **More code**: ~100 lines vs automatic cascade deletion
- **Error handling complexity**: Must handle partial failures
- **Not atomic**: Possible to delete some records but not others if error occurs

### Error Scenarios
If deletion fails mid-operation:
- Activities deleted but ActivityTypes remain → No data loss, user can retry
- ActivityTypes deleted but Caree remains → Orphaned data (rare, requires cleanup)
- Caree deleted but cache not cleared → Cache inconsistency (resolved on next refresh)

## Alternatives Considered
1. **Use `.deleteSelf` for parent references**:
   - ❌ CloudKit error: "Parent references must be CKReferenceActionNone"
   - ❌ Not allowed for shared records

2. **Leave orphaned records, clean up later**:
   - ❌ Wastes CloudKit storage quota
   - ❌ Can confuse users if they discover orphaned data
   - ❌ Harder to debug sync issues

3. **Don't support caree deletion for shared carees**:
   - ❌ Poor UX (owner can't delete own caree)
   - ✅ Actually implemented for **non-owners** (only owner can delete)

## Implementation Details

### Progress Breakdown
Total steps weighted by estimated time:
- Query ActivityTypes: 10% (fast query)
- Delete Activities: 40% (most records, batched)
- Delete ActivityTypes: 20% (medium batch)
- Delete Caree: 10% (single record)
- Cache cleanup: 20% (local SwiftData operations)

### Batch Deletion
Activities and ActivityTypes deleted in batches using CloudKit's batch operations for efficiency:
```swift
let batchOperation = CKModifyRecordsOperation(
    recordsToSave: nil,
    recordIDsToDelete: recordIDs
)
```

## Related
- CloudKitDataService implementation
- CareeDetailView deletion progress UI
- ADR 001: SwiftData + CloudKit architecture (cache cleanup)
