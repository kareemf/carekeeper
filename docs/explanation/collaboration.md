# Understanding Collaboration

CareKeeper's collaboration features enable multiple caregivers to coordinate care seamlessly. This page explains how sharing works, sync behavior, and best practices for collaborative care.

## How Collaboration Works

### The Basic Flow

1. **Owner creates a caree** with activity types
2. **Owner shares the caree** via share link
3. **Participants accept** the share invitation
4. **Everyone tracks activities** from their devices
5. **Data syncs automatically** via iCloud
6. **Notifications alert** about others' activities

[SCREENSHOT: Collaboration flow diagram]

### Real-Time Sync

When someone tracks an activity:

**Immediate** (your device):
- Activity appears instantly in your list
- UI updates optimistically
- No waiting for sync confirmation

**Seconds later** (other devices):
- CloudKit syncs in background
- Activity appears on all participants' devices
- Notifications sent (if enabled)
- Conflict resolution handles concurrent edits

[SCREENSHOT: Multi-device sync illustration]

!!! success "Instant Feel"
    CareKeeper uses optimistic UI—your changes appear immediately while syncing happens in the background. This makes the app feel instant even with slow connections.

## Sharing Model

### Caree-Level Sharing

Sharing happens at the **caree level**, not account level:

✅ **Each caree can be shared independently:**
- Share your baby with your partner
- Share your dog with your roommates
- Keep your personal health tracking private
- Different participants for different carees

❌ **You cannot:**
- Share your entire CareKeeper account
- Share multiple carees at once (share each individually)
- Have different permissions for different carees

[SCREENSHOT: Multiple carees with different participant lists]

### Automatic Inclusion

When you share a caree, participants automatically get:
- 📋 All activity types for that caree
- 📊 All existing activities (full history)
- 🔄 All future activities tracked by anyone
- ➕ Ability to create new activity types and activities

### Owner vs Participant

**Owner** (person who created the caree):
- Created the caree originally
- Can delete the caree
- Can add/remove participants
- Can stop sharing entirely
- Full edit access to all data

**Participant** (invited caregiver):
- Accepted a share invitation
- Cannot delete the caree
- Cannot manage other participants
- Can leave the share voluntarily
- Full edit access to all data

!!! note "Equal Editing Rights"
    Except for caree deletion, all participants have equal rights. This enables true collaborative care without hierarchy.

## Sync Behavior

### When Sync Happens

CloudKit sync occurs:
- 🔄 **Immediately** when you track/edit an activity
- 🔄 **Every 15 seconds** in background (if app is active)
- 🔄 **On app launch** (pulls latest data)
- 🔄 **When pull-to-refresh** is used
- 🔄 **When push notification** arrives

### Offline Behavior

If your device is offline:

1. **Track normally** - Activities saved locally
2. **Queued for sync** - Marked as "pending"
3. **Synced when online** - Automatic retry
4. **Conflict resolution** - CloudKit handles concurrent edits

[SCREENSHOT: Sync status indicator showing offline state]

!!! tip "Offline Confidence"
    Don't worry about losing data offline. Everything is saved locally and will sync when you're back online.

### Conflict Resolution

If two people edit the same activity simultaneously:

**CloudKit's automatic resolution:**
1. **Detects conflict** (same record, different versions)
2. **Chooses "winner"** (typically last-write-wins)
3. **Syncs winner** to all devices
4. **No data loss** for most conflicts

**Rare edge cases:**
- If both people delete and edit simultaneously, deletion wins
- If sync fails repeatedly, manual intervention may be needed

[SCREENSHOT: Conflict resolution illustration]

!!! note "Rare Conflicts"
    Conflicts are rare in practice because most activities are created (not edited) and edits happen on different activities.

## Notifications

### Activity Notifications

Get notified when other participants track activities:

**What you'll be notified about:**
- ✅ New activities tracked by others
- ✅ Activity types created by others
- ✅ Caree details updated by others

**What you won't be notified about:**
- ❌ Your own activities
- ❌ Carees where notifications are disabled
- ❌ Edits to existing activities (only new activities)

[SCREENSHOT: Example activity notification]

### Notification Settings

**Global toggle:**
- Settings > Notifications > Enable/disable all

**Per-caree toggle:**
- Caree detail view > Bell icon > Enable/disable for this caree

**iOS System Permissions:**
- Settings > CareKeeper > Notifications > Must be enabled

[SCREENSHOT: Notification settings]

!!! tip "Notification Fatigue"
    If a caree is very active (frequent tracking), consider disabling notifications and checking manually instead.

### Notification Content

Notifications show:
- 📱 Caree name
- 🏷️ Activity type
- 📊 Quantity (if applicable)
- 👤 Who tracked it (if identifiable)
- ⏰ When it was tracked

Tap notification to:
- 🔍 View activity details
- ✏️ Edit if needed
- 📋 See recent activity list

[SCREENSHOT: Notification with tap action]

## Best Practices

### Communication

**Before sharing:**
- 💬 Discuss what to track
- 📋 Agree on activity type names
- 📏 Decide on units (oz vs ml, etc.)
- 🔔 Set notification preferences

**During collaboration:**
- 📝 Use notes to communicate
- 🤝 Be consistent with naming
- ⏰ Track promptly (don't rely on memory)
- 📊 Review activity history together

[SCREENSHOT: Notes used for communication]

### Consistency

Keep tracking consistent across participants:

**Activity type usage:**
- ✅ Use "Bottle" for all bottle feeding
- ❌ Don't create "Bottle - Dad" and "Bottle - Mom"

**Quantity standards:**
- ✅ Always use same unit (oz or ml, not both)
- ✅ Use decimals consistently (3.5 vs 3 1/2)

**Time tracking:**
- ✅ Track at actual time or use custom time
- ❌ Don't estimate hours later

**Notes style:**
- ✅ Keep notes concise and relevant
- ❌ Don't use notes for chat (use Messages for that)

### Privacy Within Groups

Even with trusted participants:

**Be mindful:**
- 🔒 Notes are visible to all participants
- 📍 Locations are visible to all participants
- 📸 Profile photos are visible to all participants
- 📊 Full activity history is visible to all participants

**Guidelines:**
- Don't include sensitive information others shouldn't see
- Discuss privacy expectations upfront
- Update sharing if expectations change

## Common Scenarios

### Scenario 1: New Parents, Day/Night Shifts

**Setup:**
- Mom creates caree "Baby Emma"
- Shares with Dad
- Both track feeding, sleep, diapers

**Usage:**
- Dad tracks night feedings while Mom sleeps
- Mom wakes up and sees what happened overnight
- Both coordinate next steps based on history
- No need to wake each other for handoff

[SCREENSHOT: Shift-based tracking example]

### Scenario 2: Roommates Sharing Pet Care

**Setup:**
- Roommate A creates caree "Max the Dog"
- Shares with Roommates B and C
- All track walks, feeding, water

**Usage:**
- Roommate A walks dog at 7am
- Roommate B sees walk logged, skips morning walk
- Roommate C feeds dog after work
- Everyone knows current status without asking

[SCREENSHOT: Roommate pet care example]

### Scenario 3: Day Care Provider Integration

**Setup:**
- Parent creates caree "Emma"
- Shares with day care provider
- Provider tracks throughout the day

**Usage:**
- Provider logs naps, meals, diaper changes
- Parent gets notifications during work
- Parent reviews full day at pickup
- No paper logs needed

[SCREENSHOT: Day care tracking example]

### Scenario 4: Pet Care Coordination

**Setup:**
- Pet owner creates caree "Luna the Cat"
- Shares with roommates
- All track feeding, water changes, litter box cleaning

**Usage:**
- Roommate A feeds in morning
- Roommate B checks app before feeding, sees already fed
- Everyone coordinates without asking
- Track patterns for vet visits

[SCREENSHOT: Pet care coordination example]

## Advanced Topics

### Sync Architecture

CareKeeper uses CloudKit's private and shared databases:

**Private database:**
- Your owned carees
- Your activity types and activities for owned carees
- Synced across your devices only

**Shared database:**
- Carees others have shared with you
- Activity types and activities for shared carees
- Synced with all participants

[SCREENSHOT: CloudKit database architecture]

### Performance Optimization

For large shared carees (hundreds of activities):

**iOS:**
- Loads all data (no limits)
- Uses SwiftData for efficient queries
- Background refresh keeps data current

**watchOS:**
- Loads only last 48 hours of activities
- Limits to 100 activities per caree
- Clears cache on view disappear
- Optimized for memory constraints

!!! note "watchOS Limitations"
    If you need full history on watch, view on iPhone instead. The 48-hour window is intentional for performance.

### Data Consistency

CareKeeper maintains consistency through:

1. **Optimistic UI** - Shows your changes immediately
2. **Background sync** - Uploads changes asynchronously
3. **Conflict resolution** - Handles simultaneous edits
4. **Retry logic** - Re-attempts failed syncs automatically
5. **Pull-to-refresh** - Manual sync trigger for users

This architecture provides both speed and reliability.

## Related Topics

- [How to Share a Caree](../how-to/share-caree.md)
- [Security & Privacy](security-privacy.md)
- [FAQ](../reference/faq.md)
