# CloudKit Sharing Diagnostics Guide

**Purpose**: Troubleshoot why shared Carees show up but their ActivityTypes and Activities don't.

## Current Problem (TestFlight, Real Devices)

**Observed**:
- ✅ Shared Carees appear in the app
- ❌ No ActivityTypes for shared Carees
- ❌ No Activities for shared Carees
- ❌ Only one zone in shared database: `com.apple.coredata.cloudkit.zone`
- ❌ Only one share and one CD_Caree entity

**Expected**:
- Each accepted share should create a **custom zone** in the shared database
- Each zone should contain the CD_Caree, CD_ActivityType, and CD_Activity records
- Zone names should be like: `PCS-[GUID]` or similar (not the SwiftData default zone)

## Understanding CloudKit Sharing with SwiftData

### How It Should Work

1. **Owner creates share**:
   - Owner has Caree with ActivityTypes and Activities in **private database**
   - All in SwiftData's default zone: `com.apple.coredata.cloudkit.zone`
   - Owner creates CKShare pointing to the root Caree record
   - CKShare is saved to **private database**

2. **Participant accepts share**:
   - CloudKit creates a **new custom zone** in participant's **shared database**
   - The custom zone name is something like: `PCS-XXXXX-XXXX-XXXX`
   - CloudKit **copies** the shared records (Caree + children) to this custom zone
   - Participant queries the **shared database** to find these records

3. **SwiftData relationship cascade**:
   - When sharing a Caree, SwiftData should automatically include:
     - All ActivityTypes (because of `@Relationship(deleteRule: .cascade)`)
     - All Activities (because of `@Relationship(deleteRule: .cascade)`)
   - This happens via the `CKShare.rootRecord` and CloudKit's parent-child relationships

### Why It's Not Working

**Hypothesis 1: SwiftData not establishing parent relationships**
- SwiftData might not be setting up proper CKRecord parent references
- Without parent references, child records aren't included in the share
- Result: Only the root Caree is shared, children stay in owner's private database

**Hypothesis 2: Share created before children sync**
- If share is created immediately after Caree creation
- Child ActivityTypes/Activities might not have synced to CloudKit yet
- Share only includes what exists at share creation time
- Later additions don't automatically get added to existing shares

**Hypothesis 3: Custom zone not being created**
- If only seeing `com.apple.coredata.cloudkit.zone` in shared database
- This suggests CloudKit might be confused about zone ownership
- Should see custom zones like `PCS-XXXXX` for each share

## Diagnostic Steps

### Step 1: Check CloudKit Dashboard (Owner's Perspective)

1. Go to [CloudKit Console](https://icloud.developer.apple.com/)
2. Select your app: `iCloud.com.kareemf.CareKeeperCloudKit`
3. Select **Private Database**
4. Check **Record Zones**:
   - Should see: `com.apple.coredata.cloudkit.zone`
   - This is where all your SwiftData records live

5. Query records in that zone:
   - Look for `CD_Caree` records
   - Check each Caree record for:
     - `recordID` - note the full ID
     - `share` field - should reference a CKShare if shared
     - `parent` field - should be nil (root record)

6. Look for `CD_ActivityType` records:
   - Check the `parent` field
   - **Should reference the parent CD_Caree recordID**
   - If parent is nil → That's the problem!

7. Look for `CD_Activity` records:
   - Check the `parent` field
   - **Should reference the parent CD_Caree recordID**
   - If parent is nil → That's the problem!

8. Look for `cloudkit.share` records:
   - These are the CKShare records
   - Check `rootRecord` - should point to a CD_Caree
   - Check `participants` - should list owner + participants

### Step 2: Check CloudKit Dashboard (Participant's Perspective)

1. Log in to CloudKit Console with participant's iCloud account
2. Select **Shared Database**
3. Check **Record Zones**:
   - Should see custom zones: `PCS-XXXXX-XXXX-XXXX` (one per accepted share)
   - Should NOT only see `com.apple.coredata.cloudkit.zone` (that's private)

4. Query each custom zone:
   - Should see `CD_Caree` records
   - Should see `CD_ActivityType` records
   - Should see `CD_Activity` records
   - All should have proper parent references

### Step 3: Check App Logs

Add logging to `CloudKitSharedRecordsService.fetchSharedCarees()`:

```swift
// After fetching zones
logger.info("📱 Found \(zones.count) shared zones:")
for zone in zones {
    logger.info("  - \(zone.zoneID.zoneName) (owner: \(zone.zoneID.ownerName))")
}
```

**Expected output**:
```
📱 Found 3 shared zones:
  - _defaultZone (owner: __defaultOwner__)
  - PCS-12345-ABCD (owner: _a1b2c3d4e5f6)
  - PCS-67890-WXYZ (owner: _f6e5d4c3b2a1)
```

**Bad output** (what you're seeing):
```
📱 Found 1 shared zones:
  - com.apple.coredata.cloudkit.zone (owner: ???)
```

### Step 4: Test Share Creation Flow

On the owner's device, add logging to `CloudKitSharingService.createOrGetShare()`:

```swift
// Before creating share
logger.info("🔍 Found Caree CKRecord: \(careeCKRecord.recordID)")
logger.info("   Parent: \(String(describing: careeCKRecord.parent))")
logger.info("   Share: \(String(describing: careeCKRecord.share))")

// After creating share
logger.info("✅ Created share: \(share.recordID)")
logger.info("   Root record: \(String(describing: share.rootRecord))")
```

Check if the Caree has a parent (should be nil for root) and if share creation succeeds.

### Step 5: Check SwiftData Model Configuration

In `Caree.swift`, verify relationships:

```swift
@Relationship(deleteRule: .cascade, inverse: \ActivityType.caree)
var activityTypes: [ActivityType]? = []

@Relationship(deleteRule: .cascade, inverse: \Activity.caree)
var activities: [Activity]? = []
```

✅ This looks correct - cascade should work.

But for CloudKit, you also need **parent references**. SwiftData should handle this automatically, but might not be.

## Common Issues & Solutions

### Issue 1: Parent References Missing

**Symptom**: Child records exist in private DB but aren't included in share.

**Root Cause**: SwiftData not setting `parent` field on CKRecords.

**Solution**: Manually set parent references when creating ActivityTypes/Activities.

However, this is tricky with SwiftData because you don't have direct CKRecord access during creation. You'd need to:
1. Create the SwiftData objects normally
2. Wait for CloudKit sync
3. Query the CKRecords
4. Manually set parent references
5. Save back to CloudKit

This is complex and defeats the purpose of SwiftData automation.

**Better Solution**: Ensure SwiftData is properly configured with CloudKit parent-child relationships.

### Issue 2: Share Created Too Early

**Symptom**: Caree is shared, but ActivityTypes/Activities added later don't appear.

**Root Cause**: Share only includes records that exist at share creation time.

**Solution**:
- Wait for full CloudKit sync before allowing share creation
- Show sync status indicator
- Disable share button until `isSynced == true`

This is already partially implemented in `CareeShareButton` but might need strengthening.

### Issue 3: SwiftData + CloudKit Sharing Incompatibility

**Symptom**: SwiftData's automatic CloudKit sync doesn't properly support CKShare with hierarchical data.

**Root Cause**: SwiftData's CloudKit integration might have limitations with sharing complex object graphs.

**Potential Solutions**:

**Option A: Pure SwiftData Sharing (Recommended)**
- Use SwiftData's native sharing APIs (if available in iOS 18+)
- Let SwiftData handle everything
- Check: Does SwiftData have built-in sharing support?

**Option B: Hybrid Approach (Current)**
- Use SwiftData for data model
- Use CloudKit APIs for sharing
- Manually ensure parent references are set

**Option C: Full CloudKit (Nuclear Option)**
- Abandon SwiftData for shared records
- Use pure CloudKit APIs for shared carees
- Keep SwiftData only for local/private data
- Most control, but most work

### Issue 4: Zone Confusion

**Symptom**: Only seeing `com.apple.coredata.cloudkit.zone` in shared database.

**Root Cause**: This zone name should only appear in **private** database. If it's in **shared** database, something is very wrong with zone creation.

**Check**:
- Are you querying the correct database? (shared vs private)
- Is CloudKit Console showing the right database?
- Is the app correctly using `container.sharedCloudDatabase`?

## Recommended Fix Path

### Short-term Fix: Manual CloudKit Records

Since SwiftData might not be setting parent references correctly, implement a manual sync layer:

1. **When creating ActivityType/Activity**:
   - Create the SwiftData object normally
   - Wait for CloudKit export (monitor notifications)
   - Query the resulting CKRecord
   - Set the `parent` field to point to the Caree's CKRecord
   - Save back to CloudKit

2. **When sharing**:
   - Verify all child records have parent references
   - Create the share
   - Include all related records explicitly

This is implemented in the new `CloudKitParentReferenceService` (see fix).

### Long-term Fix: Investigate SwiftData Sharing

Apple might have improved SwiftData sharing in iOS 18. Check:
- WWDC 2024 videos on SwiftData
- SwiftData documentation for sharing APIs
- Sample code from Apple

If SwiftData now supports proper sharing, migrate to that.

## Testing Checklist

After implementing fix:

- [ ] Owner creates Caree with ActivityTypes and Activities
- [ ] Owner shares Caree
- [ ] Participant accepts share
- [ ] CloudKit Dashboard shows custom zone in participant's shared DB
- [ ] Custom zone contains CD_Caree, CD_ActivityType, CD_Activity
- [ ] All records have proper parent references
- [ ] Participant's app displays ActivityTypes and Activities
- [ ] Participant can create new ActivityTypes (if implemented)
- [ ] Participant can create new Activities
- [ ] New records appear in shared zone
- [ ] Owner sees participant's new records

## Debug Logging Commands

Add these to key locations:

```swift
// In CloudKitSharedRecordsService.fetchSharedCarees()
logger.info("📱 Zones: \(zones.map { $0.zoneID.zoneName }.joined(separator: ", "))")

// In CloudKitSharingService.createOrGetShare()
logger.info("🔍 Caree record parent: \(String(describing: careeCKRecord.parent?.recordID))")

// In CloudKitSharedDataService.createActivity()
logger.info("➕ Creating activity in zone: \(zoneID.zoneName)")
logger.info("   Parent caree: \(caree.id)")
```

## References

- [Apple: CloudKit Sharing](https://developer.apple.com/documentation/cloudkit/shared_records)
- [Apple: SwiftData and CloudKit](https://developer.apple.com/documentation/swiftdata/managing-model-data-in-cloudkit)
- [WWDC 2023: What's new in SwiftData](https://developer.apple.com/videos/play/wwdc2023/10187/)
- [CloudKit Best Practices](https://developer.apple.com/documentation/cloudkit/designing_and_creating_a_cloudkit_database)
