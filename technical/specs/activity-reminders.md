# Activity Reminders – Phase 1/3

## Context & Goals
CareKeeper currently records historical data. We want to prototype personal, on-device reminders tied to specific carees/activities, then optionally gate the UX per ActivityType.

**Phase 1 objectives**
1. Allow users on both iOS and watchOS to enable a reminder while creating or editing an activity.
2. When enabled, collect a future date (iOS) or minutes-from-now (watch) to schedule a local notification via EventKit Reminders.
3. Persist the reminder metadata locally (per user) so edits/deletes can update/cancel the reminder.
4. Add iconography in list/detail views to surface pending reminder state.

**Phase 2 objectives**
1. Add a boolean `hasReminders` to `ActivityType`, configure it from the create/update flows, and hide the reminder toggle for activities whose type disables reminders.

**Phase 3 objectives**
1. Update README “Features” list, docs/index.md “Features” section, and user-facing docs (FAQ, how-to) to mention reminders and how they work per device.

Reminders remain *personal* (local EventKit store only). No CloudKit syncing at this phase—each caregiver configures their own reminders.

---

## Requirements

### Reminder behavior
- Uses EventKit Reminders API (EKReminder) on both iOS and watchOS (watchOS 10+ supports EventKit).
- Permissions requested lazily the first time the toggle is enabled (same as location flow).
- Reminders include:
  - Title `"<CareeName>: <ActivityTypeName>"`
  - Notes body `"<ActivityTypeName> | <TimeAgo>"` or similar short description.
  - Due date as chosen by user (explicit date/time on iOS, `now + minutes` on watch).
  - Optional: include quantity/notes if trivial.
- Reminders auto-cancel when:
  - Activity is deleted.
  - Reminder toggle is turned off in edit view (confirm dialog).
- Editing an existing activity:
  - Shows the reminder toggle in the “on” state when metadata exists.
  - Allows users to adjust the due date or disable it.
  - Does **not** change the activity’s timestamp (reminder is standalone).
- Pending reminder indicator appears in activity list/detail rows via bell icon plus device glyph (`📱` or `⌚️`) derived from the reminder source.

### UX/flows
#### iOS – Create/Edit Activity
- Add a “Set Reminder” toggle near the custom time controls.
- When enabled:
  - Display UIDatePicker (calendar + time). Use `.dateAndTime`, allow future selections (min = now, max = now + 7 days – EventKit limit).
  - Default date = now rounded to next 5 minutes.
  - If permission not determined, present EventKit permission dialog; revert toggle if denied.
- When edited, existing reminder time populates the picker.
- When toggle disabled and reminder existed, prompt: “Disable reminder? This will delete the pending reminder.” -> Confirm/Cancel.

#### watchOS – Track/Edit Activity
- Add “Remind me” toggle (watch style).
- When enabled:
  - Show `minutes from now` crown-controlled picker (0–240 min). Default 5 min.
  - For editing, convert existing due date to minutes-from-now (if due date already passed, display 0 and a note).
- Same permission/confirmation flow as iOS; request EventKit access when first toggled.

### Data model / persistence
- Reminder metadata stored locally per activity and synchronized between phone/watch caches so edits on either device know the reminder state:
  - `reminderIdentifier` (String) – EventKit UID for cancellation/update on the originating device.
  - `reminderDueDate` (Date, optional) – used for UI display and conversions.
  - `reminderSource` (enum: `.phone` / `.watch`) – indicates which device scheduled the reminder so UI can label it.
- Metadata is **per-user**, not shared:
  - Add a new CloudKit record type `CD_ActivityReminderMetadata` in the **private database** (same custom zone as owned carees) keyed by `activityID`.
  - Record fields mirror the local metadata (`CD_activityID`, `CD_reminderIdentifier`, `CD_reminderDueDate`, `CD_reminderSourceRawValue`).
  - iOS/watch clients fetch/save/delete these records via a shared `ActivityReminderMetadataStore` so the same Apple ID sees consistent reminders across devices.
- Storage integrations:
  - Extend `LocalCacheService` and `WatchCacheService` snapshots with reminder metadata (similar to streaming logs).
  - When metadata changes locally, update the cache and upsert/delete the per-user CloudKit record.
  - When fetching activities from CloudKit (owned or shared), overlay the per-user metadata records onto the fetched activities before caching.

### Phase 2 flag (`ActivityType.hasReminders`)
- New boolean on `ActivityType` (default true).
- ActivityType create/edit screens gain a toggle (“This activity can schedule reminders”).
- Activity create/edit view checks the type’s flag at runtime:
  - If false, hide reminder UI.
  - If true, show reminder toggle with previous state (if any).
- Existing activities follow whatever the ActivityType currently states (no data migration). If a type disables reminders later, the toggle stops appearing; existing reminder data stays untouched but is effectively inaccessible unless the flag is re-enabled.

---

## Open Questions / Decisions
1. **Reminder limits** – cap future reminders at 7 days (EventKit constraint).
2. **Local persistence mechanism** – extend shared cache models and CloudKit snapshots so reminder metadata (identifier/due date) syncs between phone and watch; EventKit reminders themselves stay local.
3. **Notification payload** – use `"<Caree>: <ActivityType> | <TimeAgo> ago"` (with notes/quantity if trivial).

---

## Implementation Plan

### Phase 1 – Reminder Toggle + EventKit plumbing
1. **EventKit Utilities**
   - Add `ReminderScheduler` service (shared) handling permission requests, create/update/delete by identifier.
   - Store metadata (identifier + dueDate) inside activity snapshots/cache models.
2. **iOS UI**
   - Update activity create/edit forms with toggle + date picker.
   - Add list/detail indicator icon binding to metadata.
3. **watchOS UI**
   - Similar toggle + minutes-from-now control in `TrackActivityView` and edit flows.
   - Ensure metadata appears when editing (requires provider/snapshot updates).
4. **Data plumbing**
   - Extend shared models (`ActivitySnapshot`, local cache DB) to retain reminder metadata.
   - Create `CD_ActivityReminderMetadata` in the private CloudKit database plus an `ActivityReminderMetadataStore` wrapper (save/fetch/delete).
   - Ensure refresh flows fetch metadata records for the signed-in user and overlay them on the fetched activities before caching.
5. **Lifecycle hooks**
   - When saving/deleting activities (both platforms), call scheduler to create/update/remove reminders.
   - After local metadata changes, upsert/delete the per-user metadata record via the store.
   - When viewing activities, cleanup reminders whose due date already passed? (Optional future enhancement.)

### Phase 2 – Deferred (future) ActivityType flag
- Currently tracked as a follow-up, not in active scope. Captured in Potential Improvements below.

### Phase 3 – Documentation & Marketing
1. Update README “Features” section and docs/index.md to list reminders.
2. Update docs/reference/faq.md and relevant how-to guides with reminder setup steps, permissions, and platform behavior.
3. Screenshots to capture:
   - `[SCREENSHOT: iOS Activity detail view showing reminder toggle and date picker]`
   - `[SCREENSHOT: watchOS Track Activity view showing reminder toggle with minutes-from-now crown control]`

---

## Tracking
- **Open questions** listed above – resolve before implementation.
- After approval, create subtasks:
  - `feat/reminders-phase1` (EventKit service + UI)
  - `feat/reminders-phase2` (ActivityType flag)
- Testing:
  - Unit tests for reminder scheduler (identifier persistence).
  - Manual tests on device + watch simulator for scheduling, editing, deleting.

Once we iterate on this spec and lock the remaining details, we can start Phase 1 implementation. Let me know if anything needs refinement or if there are additional UX considerations (e.g., deep linking from notifications to specific caree/activity). 

## Potential Improvements (Future Work)
1. **ActivityType `hasReminders` flag** – gate the reminder UI by activity type to reduce watch UI clutter. Requires CloudKit schema update + snapshot/service changes.
2. **Cross-device auto scheduling** – when iOS receives a watch-originated reminder metadata update (or vice versa), consider auto-creating/canceling the local reminder so actions propagate between devices.
