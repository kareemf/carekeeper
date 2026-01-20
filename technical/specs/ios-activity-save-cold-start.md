# iOS Activity Save Cold Start (Background Refresh Preservation)

**Status**: Updated  
**Created**: 2026-02-22  
**Last Updated**: 2026-02-22  
**Author**: Codex  
**Audience**: iOS, CloudKit, SwiftData

---

## Problem Summary
- Owned activity creation can succeed while a background refresh is rebuilding the cache.
- During refresh, `replaceCaree` deletes existing child records and rebuilds from the CloudKit snapshot.
- If the snapshot is stale (missing newly created activities), those local activities are deleted and "pop" from the UI.

## Goals
- **Correctness**: Newly created activities survive a background refresh even if CloudKit snapshots lag.
- **Predictability**: Preserve local-only records until they appear in a CloudKit snapshot or are deleted locally.
- **Minimal UI impact**: Avoid additional UI merge logic in this branch.

## Design Overview
### Pending preservation tracking
Maintain in-memory sets of locally created records:
- `pendingLocalActivityIDs`
- `pendingLocalActivityTypeIDs`

These IDs represent local creations that may not have appeared in CloudKit yet. They are used to prevent `replaceCaree` from deleting them during background refresh.

### Lifecycle rules
1. **Mark pending on local creation**
   - When an Activity or ActivityType is cached from a local create flow, add its ID to the pending set.
2. **Prune when seen in snapshot**
   - During `replaceCaree`, remove pending IDs that are present in the incoming CloudKit snapshot.
3. **Preserve during refresh**
   - When rebuilding children, keep any existing child whose ID is still pending.
4. **Clear on local deletion**
   - If a user deletes an activity/activity type locally, remove its ID from pending.
5. **Do not blanket-clear on refresh end**
   - `endBackgroundRefresh()` no longer wipes pending sets. They only shrink via snapshot presence or local delete.
6. **Preserve activity types for pending activities**
   - ActivityTypes associated with pending Activities are preserved to avoid cascade deletions.
7. **Separate cache store file**
   - The LocalCacheService uses a dedicated store (`cache.store`) so CoreData+CloudKit mirroring cannot delete cache objects.

## Edge Case
If an activity is:
1) created locally,
2) synced to CloudKit,
3) deleted by another client before this device sees it in a snapshot,
4) then a refresh pulls a snapshot that still omits it,
the activity remains in `pendingLocalActivityIDs` and will be preserved.

**Mitigation**: The user can delete the activity locally; this clears the pending ID and removes it from the cache.

## Implementation Notes
- Pending IDs persist across refresh boundaries.
- Pending IDs are pruned in `replaceCaree` by subtracting incoming snapshot IDs.
- Pending IDs are removed when `removeCachedActivity` / `removeCachedActivityType` runs.
- Pending Activities force preservation of their ActivityTypes to keep relationships intact.
- Cache uses a separate store file to isolate from CloudKit sync.

## Validation Checklist
- Create an activity immediately before a background refresh: it should remain after refresh.
- Create an activity during a background refresh: it should remain after refresh.
- Delete a pending activity locally: it should be removed and no longer preserved.
