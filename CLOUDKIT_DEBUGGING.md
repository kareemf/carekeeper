# CloudKit Sync Debugging Guide

## Console Log Messages to Watch For

### On App Launch
- `🔧 Initializing ModelContainer with CloudKit sync`
- `✅ ModelContainer created successfully`
- `✅ iCloud account: Available` ← **MUST SEE THIS**
- `❌ iCloud account: No account signed in` ← **Problem if you see this**

### When Creating a Caree
- `➕ Creating new caree: [Name] (ID: [UUID])`
- `💾 Saving to SwiftData...`
- `✅ Save successful - SwiftData will sync to CloudKit automatically`
- `⏳ CloudKit sync typically takes 5-15 seconds`

### When Sharing
- `📤 Share button tapped for caree: [Name] (ID: [UUID])`
- `🆕 No existing share found - will create new share`
- `✅ Caree record found in CloudKit - ready to share` ← **GOOD!**
- `⚠️ Caree record not yet synced to CloudKit` ← **Wait or pull-to-refresh**

### In CloudSharingView
- `☁️ iCloud account status: 1` (1 = available)
- `🔍 Attempting to fetch CloudKit record with ID: [UUID]`
- `✅ Successfully fetched record: [UUID]`
- `💾 Saving share to CloudKit...`
- `✅ Share saved successfully`

## Common Issues & Solutions

### 1. "iCloud account: No account signed in"
**Problem:** Not signed into iCloud on device/simulator

**Fix:**
- **Simulator:** Settings → Apple ID → Sign in
- **Device:** Settings → [Your Name] → iCloud
- Ensure "iCloud Drive" is enabled

### 2. "Caree record not yet synced to CloudKit"
**Problem:** SwiftData hasn't synced to CloudKit yet

**Fix:**
- Wait 10-15 seconds after creating caree
- Pull down to refresh in CareeDetailView
- Check CloudKit Dashboard for records

### 3. No Sync Messages in Console
**Problem:** SwiftData sync might be failing silently

**Debug Steps:**
1. Check Console for CoreData errors:
   ```
   grep -i "coredata\|cloudkit\|nspersistent" in Xcode console
   ```

2. Enable verbose CloudKit logging:
   - Edit Scheme → Run → Arguments → Environment Variables
   - Add: `com.apple.coredata.CloudKitDebug` = `3`

3. Check entitlements are correct:
   ```bash
   codesign -d --entitlements :- /path/to/app
   ```

### 4. "Zone Not Found" Error
**Problem:** CloudKit zones not created yet

**Fix:**
- Normal on first sync!
- Wait for SwiftData to create zones
- Pull to refresh

### 5. Records Not Appearing in CloudKit Dashboard
**Check:**
1. Go to https://icloud.developer.apple.com/
2. Select container: `iCloud.com.kareemf.CareKeeperCloudKit`
3. Go to Data → Private Database → Query Records
4. Look for record types: `CD_Caree`, `CD_ActivityType`, `CD_Activity`

**If no records:**
- App hasn't synced yet
- Wrong container selected
- iCloud account issue
- Network issue

## Manual CloudKit Verification

### Check if Record Exists
```swift
// Already implemented in CloudKitSyncService.isSynced()
// Watch console for:
print("✅ Caree record found in CloudKit - ready to share")
// or
print("⚠️ Caree record not yet synced to CloudKit")
```

### Force Sync Check
In CareeDetailView:
1. Pull down to refresh
2. Watch console for sync status update
3. Sync indicator should change: ☁️⃠ → ☁️✓

## Network Debugging

### Check Network Activity
In Xcode:
1. Debug → Debug Workflow → View Network Traffic
2. Look for requests to `icloud.com`
3. Should see CloudKit API calls

### Enable CloudKit Verbose Logging
Add to scheme environment variables:
```
com.apple.coredata.CloudKitDebug = 3
OS_ACTIVITY_MODE = disable
```

## Container Verification

### Verify Container ID
```bash
grep -r "CareKeeperCloudKit" CareKeeperV2/
```

Should show: `iCloud.com.kareemf.CareKeeperCloudKit` everywhere

### Verify Entitlements
Check files contain correct container:
- `CareKeeperV2/CareKeeperV2.entitlements`
- `CareKeeperV2 Watch App/CareKeeperV2 Watch App.entitlements`

## Reset & Retry

If sync completely broken:

1. **Delete app completely**
   ```bash
   xcrun simctl uninstall booted com.kareemf.CareKeeper
   ```

2. **Clear derived data**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/CareKeeper-*
   ```

3. **Rebuild fresh**
   ```bash
   xcodegen generate
   xcodebuild clean build -scheme CareKeeper
   ```

4. **Check CloudKit Dashboard**
   - Verify container exists
   - Check development environment is selected

5. **Reinstall and test**

## Expected Timeline

After creating a caree:
- **0s:** Saved to local SwiftData
- **1-5s:** SwiftData queues CloudKit sync
- **5-15s:** CloudKit sync completes
- **15s+:** Pull-to-refresh to verify

After pull-to-refresh:
- **Immediate:** Check if record exists in CloudKit
- Sync indicator updates: ☁️✓ or ☁️⃠

## Success Indicators

✅ All working correctly:
1. `✅ iCloud account: Available` on launch
2. `✅ Save successful` when creating caree
3. Wait 15 seconds
4. Pull to refresh
5. See `✅ Caree record found in CloudKit`
6. Sync indicator shows ☁️✓
7. Share button works without alert

## Still Not Working?

Check in order:
1. ✅ iCloud account signed in?
2. ✅ Container `iCloud.com.kareemf.CareKeeperCloudKit` exists in CloudKit Dashboard?
3. ✅ App has iCloud entitlements in provisioning profile?
4. ✅ Network connectivity working?
5. ✅ No console errors during save?
6. ✅ Waited at least 30 seconds after creating caree?
7. ✅ Tried pull-to-refresh multiple times?

If all yes and still not working, check CloudKit status page:
https://www.apple.com/support/systemstatus/
