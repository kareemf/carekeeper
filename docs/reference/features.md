# Features Reference

Complete reference of all CareKeeper features, organized by category.

## Core Features

### Caree Management

**Create Carees**
- Add unlimited carees
- Set name and profile photo
- Automatic iCloud sync

**Edit Carees**
- Update name
- Change or remove photo
- Reorder in list

**Delete Carees**
- Owner-only permission
- Cascading deletion (removes all activity types and activities)
- Confirmation required

**Platforms:** iOS

---

### Activity Type Management

**Create Activity Types**
- Custom names
- Emoji or SF Symbol icons
- Quantity tracking (optional)
- Location tracking (optional)
- Per-caree organization

**Configure Quantity Tracking**
- Enable/disable per activity type
- Custom units (oz, ml, mg, min, etc.)
- Decimal precision support

**Configure Location Tracking**
- Enable/disable per activity type
- Automatic location capture
- iOS location permission required

**Edit Activity Types**
- Modify name, icon, settings
- Swipe-to-edit on iOS
- Tap-to-edit on watchOS

**Delete Activity Types**
- Cascading deletion (removes all activities of that type)
- Confirmation required

**Reorder Activity Types**
- Drag-and-drop on iOS
- Reflects on watch

**Platforms:** iOS (create/edit), watchOS (view only)

---

### Activity Tracking

**Track Activities (iOS)**
- Tap activity type to track
- Automatic timestamp (now)
- Custom date/time picker
- Optional quantity entry
- Optional location capture
- Optional notes field

**Track Activities (watchOS)**
- Tap activity type button
- Digital Crown for quantity
- Automatic timestamp (now)
- Custom time toggle
- Instant confirmation

**Edit Activities**
- Modify quantity
- Change date/time
- Update notes (iOS only)
- Update location (iOS only)

**Delete Activities**
- Swipe-to-delete (iOS)
- Tap-to-delete (watchOS)
- Confirmation required

**View Activities**
- Recent activities (caree detail view)
- Full activity list
- Filter by activity type
- Reverse chronological order

**Platforms:** iOS (full features), watchOS (quantity and time only)

---

## Collaboration Features

### Sharing

**Share Carees**
- Per-caree sharing
- Share via Messages, Mail, AirDrop, etc.
- Invite unlimited participants
- CloudKit-powered

**Accept Shares**
- Tap share link to accept
- One-tap acceptance
- Automatic sync after acceptance

**Manage Participants**
- View participant list
- Remove participants (owner only)
- Leave share (participant)

**Permissions**
- Owner: Full control, can delete caree
- Participant: Edit access, cannot delete caree
- All: Create/edit/delete activities and activity types

**Platforms:** iOS (iOS 13+ for sharing UI)

---

### Notifications

**Activity Notifications**
- Push notifications for new activities
- Tracked by other participants
- Filter out own activities
- Caree name + activity type + quantity

**Notification Settings**
- Global enable/disable
- Per-caree toggle
- iOS notification permission required

**Notification Actions**
- Tap to view activity detail
- Direct deep link to activity

**Platforms:** iOS, watchOS

---

### Sync

**Automatic Sync**
- iCloud/CloudKit-powered
- Real-time across devices
- Background sync
- Offline queue with retry

**Manual Refresh**
- Pull-to-refresh on lists
- Manual retry on errors

**Sync Status Indicator**
- Ready, Syncing, Synced, Failed states
- Visible in settings or toolbar

**Conflict Resolution**
- Automatic via CloudKit
- Last-write-wins for most cases

**Platforms:** iOS, watchOS

---

## Platform-Specific Features

### iOS-Only Features

**Caree Management**
- Create, edit, delete carees
- Photo picker integration
- Reordering with drag handles

**Activity Type Management**
- Create, edit, delete activity types
- Icon picker (emoji + SF Symbols)
- Quantity and location configuration

**Activity Details**
- Full edit capabilities
- Notes field
- Location capture and display

**Sharing**
- Share carees via share sheet
- Manage participants
- Accept shares

**Data Export**
- Export to JSON
- All data or per-caree
- Share or save to Files

**Data Import**
- Import from JSON
- Merge or replace options

**Settings**
- iCloud sync status
- Notification preferences
- Debug options

---

### watchOS-Only Features

**Digital Crown Input**
- Adjust quantities
- Scroll time picker
- Smooth analog control

**Complications**
- Circular, rectangular, inline, corner
- Show today's activity count
- Tap to open app

**Optimized UI**
- Large tap targets
- Minimal navigation
- Focus on speed

**Memory Management**
- 48-hour activity window
- Active cache clearing
- Background task cancellation

---

## Data Features

### Export

**Export Formats**
- JSON (structured data)
- Human-readable
- Machine-parseable

**Export Scope**
- All carees
- Single caree

**Export Content**
- Caree details
- Activity types
- Activities
- Metadata (IDs, timestamps)

**Platforms:** iOS

---

### Import

**Import Formats**
- JSON (CareKeeper export format)

**Import Modes**
- Merge (add to existing data)
- Replace (overwrite existing data)

**Duplicate Detection**
- UUID-based
- Skips existing records

**Platforms:** iOS

---

## Security & Privacy Features

### Encryption

**At Rest**
- Device: File Protection Complete
- iCloud: Infrastructure-level encryption
- AES-256 encryption

**In Transit**
- TLS 1.3
- Certificate pinning
- Man-in-the-middle protection

---

### Authentication

**iCloud Account**
- Apple ID sign-in
- Two-factor authentication support
- No separate CareKeeper account

---

### Access Control

**Per-Caree Sharing**
- Invite-only
- Explicit acceptance required
- Revocable by owner

**Participant Permissions**
- Equal edit rights
- Owner-only deletion

---

## UI/UX Features

### Navigation

**iOS**
- Tab-based main navigation
- NavigationStack for drill-down
- Swipe back gestures

**watchOS**
- Single NavigationStack
- Digital Crown scrolling
- Swipe back gestures

---

### Animations

**List Operations**
- Fade in/out for add/delete
- Smooth reordering
- Pull-to-refresh animation

**Activity Tracking**
- Confirmation checkmarks
- Success toast (watchOS)
- Loading indicators

**Empty States**
- Symbol effects
- Helpful prompts

---

### Accessibility

**iOS**
- VoiceOver support
- Dynamic Type (text sizing)
- High contrast support
- Reduced motion support

**watchOS**
- VoiceOver support
- Large tap targets
- Haptic feedback

---

## Limitations

### Known Limitations

**watchOS:**
- 48-hour activity window (not full history)
- 100 activities max per caree
- 50 activity types max per caree
- Cannot create/edit carees
- Cannot create/edit activity types
- Cannot edit notes

**Sharing:**
- No granular permissions (all or nothing)
- No read-only access
- Cannot share multiple carees at once
- CloudKit-dependent (requires iCloud)

**Export:**
- JSON format only (no CSV, PDF, etc.)
- No automatic scheduled exports
- No cloud backup beyond iCloud

**General:**
- No third-party integrations
- No advanced analytics/reporting
- No custom themes
- iOS/watchOS only (no Android, web)

---

## Version Information

**Current Version:** 1.0
**Minimum iOS:** 18.0
**Minimum watchOS:** 10.0
**iCloud:** Required

---

## Feature Comparison

| Feature | iOS | watchOS |
|---------|-----|---------|
| Create carees | ✅ | ❌ |
| View carees | ✅ | ✅ |
| Edit carees | ✅ | ❌ |
| Delete carees | ✅ | ❌ |
| Create activity types | ✅ | ❌ |
| View activity types | ✅ | ✅ |
| Track activities | ✅ | ✅ |
| Edit activities | ✅ | ✅ (quantity/time only) |
| Delete activities | ✅ | ✅ |
| View activity history | ✅ (full) | ✅ (48 hours) |
| Filter activities | ✅ | ✅ |
| Share carees | ✅ | ❌ |
| Accept shares | ✅ | Auto (via iPhone) |
| Notifications | ✅ | ✅ |
| Export data | ✅ | ❌ |
| Import data | ✅ | ❌ |
| Complications | ❌ | ✅ |
| Digital Crown input | ❌ | ✅ |

---

## Related Topics

- [How-To Guides](../how-to/track-activity.md) - Step-by-step instructions
- [Troubleshooting](troubleshooting.md) - Solutions to common issues
- [FAQ](faq.md) - Frequently asked questions
