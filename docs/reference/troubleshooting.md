# Troubleshooting Guide

Solutions to common issues in CareKeeper. If you don't find your issue here, see the [FAQ](faq.md) or contact support.

## Installation & Setup

### App Won't Install

**Symptoms:**
- Download stuck at "Waiting..."
- "Unable to Install" error
- App icon grayed out

**Solutions:**
1. Check available storage: Settings > General > iPhone Storage (need ~50MB free)
2. Restart your device
3. Sign out and back into App Store: Settings > [Your Name] > Media & Purchases
4. Try installing from different network (WiFi vs cellular)
5. Check iOS version: CareKeeper requires iOS 18.0+

---

### Cannot Sign Into iCloud

**Symptoms:**
- "iCloud Unavailable" message
- Sync stuck on "Connecting..."
- "Sign in to iCloud" prompt

**Solutions:**
1. Verify iCloud sign-in: Settings > [Your Name]
2. Enable iCloud Drive: Settings > [Your Name] > iCloud > iCloud Drive
3. Check Apple system status: [apple.com/support/systemstatus](https://www.apple.com/support/systemstatus/)
4. Restart device
5. Sign out and back into iCloud (Settings > [Your Name] > Sign Out)

⚠️ **Warning:** Signing out of iCloud may affect other apps. Back up important data first.

---

## Sync Issues

### Data Not Syncing Between Devices

**Symptoms:**
- Activities tracked on iPhone don't appear on watch
- Changes on one device not reflected on another
- "Sync Failed" status

**Solutions:**

**Check basics:**
1. ✅ Both devices signed into same iCloud account
2. ✅ Both devices connected to internet
3. ✅ CareKeeper open on both devices
4. ✅ Pull down to refresh on both devices

**iOS-specific:**
1. Check sync status: Settings (gear icon) > Sync Status
2. Tap "Retry" if sync failed
3. Force quit CareKeeper and reopen
4. Toggle airplane mode off/on to reset network

**watchOS-specific:**
1. Open watch app (triggers sync)
2. Wait 10-15 seconds for first sync
3. Check iPhone connectivity: Control Center > iPhone icon
4. Force quit watch app: Hold side button, swipe right on CareKeeper

**Nuclear option:**
1. Export data from iPhone (Settings > Export Data)
2. Delete CareKeeper from both devices
3. Reinstall CareKeeper
4. Import data backup

[SCREENSHOT: Sync status indicator locations]

---

### "Sync Failed" Error

**Symptoms:**
- Red "Sync Failed" indicator
- Cannot track activities
- Changes not saving

**Solutions:**

**Immediate fixes:**
1. Check internet connection
2. Tap "Retry" button
3. Pull down to refresh
4. Wait 30 seconds and try again

**If persistent:**
1. Check iCloud storage: Settings > [Your Name] > iCloud > Manage Storage
   - Free up space if full (CareKeeper needs minimal space, but iCloud quota must have room)
2. Disable and re-enable iCloud Drive:
   - Settings > [Your Name] > iCloud > iCloud Drive > Toggle OFF then ON
3. Check Apple system status for CloudKit outages
4. Restart device
5. Contact support if issue persists >24 hours

---

### Duplicate Activities Appearing

**Symptoms:**
- Same activity listed twice
- Ghost activities that can't be deleted

**Causes:**
- Sync conflict (rare)
- Network interruption during save
- Force quit during sync

**Solutions:**
1. Delete duplicate manually (swipe left > Delete)
2. Pull down to refresh (should resolve ghost entries)
3. Force quit and reopen app
4. If persistent, export data, reinstall app, import data

---

## Sharing Issues

### Cannot Share Caree

**Symptoms:**
- Share button doesn't work
- Share sheet doesn't appear
- Error when tapping Share

**Solutions:**
1. Verify you're the owner (not a participant)
2. Check internet connection
3. Verify signed into iCloud
4. Force quit and reopen CareKeeper
5. Try sharing via different method (Messages vs Mail)

---

### Participant Cannot Accept Share

**Symptoms:**
- Share link doesn't open CareKeeper
- "Cannot Open" error
- Link takes to App Store but doesn't accept share after install

**Solutions:**

**Recipient should:**
1. Verify signed into iCloud: Settings > [Your Name]
2. Install CareKeeper if not installed
3. Open CareKeeper first, then tap share link
4. Wait 5-10 seconds after tapping link
5. Check internet connection

**Sender should:**
1. Verify share was sent successfully
2. Try sending new share link
3. Try different sharing method (copy link, send via Messages)

---

### Shared Caree Not Appearing

**Symptoms:**
- Accepted share but caree doesn't appear
- "Loading..." stuck forever

**Solutions:**
1. Pull down to refresh caree list
2. Wait 30 seconds (initial sync can be slow)
3. Force quit and reopen CareKeeper
4. Check internet connection
5. Verify share wasn't revoked by owner

---

### Cannot Remove Participant

**Symptoms:**
- Participant still appears after removal
- Removed participant still has access

**Solutions:**
1. Wait 2-3 minutes for change to propagate
2. Force quit CareKeeper on both devices
3. Removed participant should also force quit and reopen
4. Pull down to refresh on both devices
5. If persistent, stop sharing entirely and re-share with desired participants

---

## Activity Tracking Issues

### Cannot Track Activity

**Symptoms:**
- Save button grayed out
- "Cannot Save" error
- Activity doesn't appear after saving

**Solutions:**

**Check required fields:**
1. ✅ Activity type selected
2. ✅ Quantity entered (if required)
3. ✅ Date/time selected

**Other fixes:**
1. Check internet connection (required for shared carees)
2. Verify you have permission (participant vs owner)
3. Force quit and reopen app
4. Try tracking different activity type
5. Check sync status

---

### Location Not Capturing

**Symptoms:**
- "Location unavailable" message
- Activity saves without location
- Location spinner forever

**Solutions:**

**Grant permissions:**
1. Settings > CareKeeper > Location
2. Select "While Using the App" or "Always"
3. Reopen CareKeeper

**Other fixes:**
1. Enable Location Services: Settings > Privacy & Security > Location Services > ON
2. Check cellular/GPS signal (go outside if indoors)
3. Toggle airplane mode off/on
4. Restart device
5. Try tracking at different location

---

### Quantity Not Saving

**Symptoms:**
- Enter quantity but appears as 0
- Quantity field resets when saving

**Solutions:**
1. Make sure activity type has "Has Quantity" enabled
2. Tap quantity field before entering value
3. Use decimal point correctly (3.5 not 3,5)
4. Don't include unit in quantity field (enter "3.5" not "3.5 oz")
5. Edit activity type to enable quantity if disabled

---

## Watch App Issues

### Watch App Not Syncing

**Symptoms:**
- Carees don't appear on watch
- Activities tracked on watch don't appear on phone

**Solutions:**

**Basic checks:**
1. ✅ Watch connected to iPhone (Control Center > iPhone icon green)
2. ✅ Both signed into same iCloud account
3. ✅ Open CareKeeper on both devices
4. ✅ Wait 15-30 seconds

**iOS fixes:**
1. Open CareKeeper on iPhone (triggers sync to watch)
2. Pull down to refresh caree list
3. Force quit CareKeeper on iPhone and reopen

**watchOS fixes:**
1. Open watch app (tap icon, don't use complication)
2. Pull down to refresh
3. Force quit watch app and reopen
4. Restart Apple Watch

**Reinstall watch app:**
1. iPhone: Watch app > My Watch > CareKeeper > Show App on Apple Watch (toggle OFF)
2. Wait 30 seconds
3. Toggle ON
4. Open CareKeeper on watch

---

### Cannot Adjust Quantity on Watch

**Symptoms:**
- Digital Crown doesn't work
- Quantity stuck at 0

**Solutions:**
1. Make sure you're on quantity adjustment screen
2. Try tapping quantity value first
3. Clean Digital Crown (lint/debris can affect)
4. Restart Apple Watch
5. Try different activity type

---

### Watch App Slow or Crashing

**Symptoms:**
- App laggy
- App crashes when opening
- "Memory Warning" in logs

**Solutions:**

**Free up memory:**
1. Force quit other watch apps
2. Restart Apple Watch
3. Reduce number of activity types (watch loads all)
4. Clear cache by force quitting CareKeeper

**If persistent:**
1. Uninstall and reinstall watch app
2. Check watchOS storage: Watch app > General > Usage
3. Update watchOS: Watch app > General > Software Update
4. Reset Apple Watch (last resort, backs up first)

---

### Complication Not Updating

**Symptoms:**
- Activity count stuck at old value
- Complication shows wrong data

**Solutions:**
1. Complications update every 15 minutes (Apple limitation)
2. Remove and re-add complication to watch face
3. Force quit CareKeeper and reopen
4. Restart Apple Watch
5. Try different complication style

---

## Notification Issues

### Not Receiving Notifications

**Symptoms:**
- No notifications for others' activities
- Notifications enabled but not appearing

**Solutions:**

**Check permissions:**
1. Settings > Notifications > CareKeeper > Allow Notifications (ON)
2. Settings > Notifications > CareKeeper > Lock Screen/Notification Center/Banners (enabled)
3. Do Not Disturb OFF (unless configured to allow CareKeeper)

**Check CareKeeper settings:**
1. Open CareKeeper > Settings (gear icon) > Notifications (ON)
2. Open caree detail > Bell icon (ON for that caree)

**Other fixes:**
1. Disable and re-enable notifications in iOS Settings
2. Sign out and back into iCloud
3. Reinstall CareKeeper
4. Check network connection (push notifications require internet)

---

### Too Many Notifications

**Symptoms:**
- Notification spam
- Dozens of notifications per day

**Solutions:**
1. Disable notifications for high-frequency carees:
   - Open caree detail > Bell icon > Toggle OFF
2. Disable notifications globally:
   - Settings > Notifications > Disable
3. Adjust iOS notification summary:
   - Settings > Notifications > Scheduled Summary

---

## Data & Export Issues

### Export Fails

**Symptoms:**
- "Export Failed" error
- Share sheet doesn't appear
- Export stuck on "Preparing..."

**Solutions:**
1. Check available storage (need space for JSON file)
2. Try exporting single caree instead of all data
3. Force quit and reopen CareKeeper
4. Restart device
5. Try exporting after sync completes

---

### Import Fails

**Symptoms:**
- "Invalid File" error
- Import hangs forever
- No data appears after import

**Solutions:**

**Verify file:**
1. Check file is .json extension
2. Validate JSON syntax: [jsonlint.com](https://jsonlint.com)
3. Verify file is CareKeeper export (not modified)
4. Check file size (very large files may timeout)

**Other fixes:**
1. Try importing smaller portions (single caree exports)
2. Check internet connection (import syncs to iCloud)
3. Force quit and retry
4. Restart device

---

## Performance Issues

### App Slow or Laggy

**Symptoms:**
- UI stuttering
- Delays when tapping
- Slow list scrolling

**Solutions:**

**iOS:**
1. Close other apps (double-tap home, swipe up)
2. Check available storage (Settings > General > iPhone Storage)
3. Restart device
4. Update iOS (Settings > General > Software Update)
5. Export data, delete app, reinstall, import data

**watchOS:**
1. Force quit other watch apps
2. Restart Apple Watch
3. Clear watch cache by force quitting CareKeeper
4. Reinstall watch app

---

### Battery Drain

**Symptoms:**
- Significant battery usage
- Device warm when using CareKeeper
- Battery drains quickly

**Solutions:**

**Check battery usage:**
1. Settings > Battery > Battery Usage by App
2. CareKeeper should be <5% for typical usage

**If high:**
1. Disable background refresh: Settings > General > Background App Refresh > CareKeeper (OFF)
2. Reduce notification frequency (disable for some carees)
3. Force quit when not in use
4. Check for iOS updates (may fix battery bugs)

**Note:** Normal usage (tracking 10-20 activities/day) should have minimal battery impact (<2%).

---

## Error Messages

### "Model Container Failed"

**Meaning:** SwiftData database couldn't initialize

**Solutions:**
1. Restart app
2. Restart device
3. Check available storage
4. Reinstall app (data may be lost)

---

### "Network Unavailable"

**Meaning:** No internet connection for CloudKit

**Solutions:**
1. Check WiFi/cellular connection
2. Toggle airplane mode off/on
3. Test in Safari (browse to apple.com)
4. Connect to different network

---

### "iCloud Account Issue"

**Meaning:** Problem with iCloud sign-in

**Solutions:**
1. Settings > [Your Name] > Check sign-in status
2. Settings > iCloud > iCloud Drive > Enable
3. Sign out and back in (backs up data first)

---

## Getting Help

If none of these solutions work:

1. **Check Apple system status:** [apple.com/support/systemstatus](https://www.apple.com/support/systemstatus/)
   - Look for CloudKit outages
2. **Export your data:** Settings > Export Data (preserve before troubleshooting)
3. **Contact support:** [support email/link]
   - Include iOS/watchOS version
   - Include steps to reproduce
   - Include error messages

## Related Topics

- [FAQ](faq.md) - Frequently asked questions
- [Features Reference](features.md) - Complete feature list
- [Security & Privacy](../explanation/security-privacy.md) - Data protection info
