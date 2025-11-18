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
   - ✅ `ReminderScheduler` implemented (shared) handling permission requests plus create/update/delete by identifier; logs permission state so we can troubleshoot failures.
   - ✅ Reminder metadata (`identifier`, `dueDate`, `source`) now lives in shared models (`Activity`, `ActivitySnapshot`), cache DB entities, and user-specific `CD_ActivityReminderMetadata` records via `ActivityReminderMetadataStore`.
   - ✅ Added a dependency-injection friendly initializer plus unit coverage for `ensureAuthorization` so permission branches are verified without launching UI alerts.
   - ✅ iOS reminders now attach explicit `EKAlarm` entries so Reminders.app delivers notifications (previously due dates existed without alarms, so no alert fired even though records appeared).
   - ✅ Reminder payloads now append the activity’s note (if provided) so the user sees their context directly in the Reminders app / notification.
   - ✅ Editing a reminder that has already been resolved/checked off now discards the completed EKReminder and schedules a fresh one so users can “restart” reminders without manual cleanup.
2. **iOS UI**
   - ✅ Activity create/edit forms expose the reminder toggle + date picker; reminder indicators render in list/detail rows with bell + device glyph.
   - ✅ Editing flows now initialize the reminder picker with the existing due date (even if it’s already in the past) so users don’t see a random future timestamp when adjusting a previously scheduled reminder.
   - ✅ Reminder badges in list/detail views now use SF Symbols (`bell.fill`, `iphone`, `applewatch`) with neutral colors instead of emojis/orange text for consistency with the rest of the UI.
3. **watchOS UI**
   - ✅ Toggle + minutes-from-now picker UI in `TrackActivityView` with Digital Crown.
   - ✅ Reminder scheduling/canceling now flows through `ReminderScheduler` (UNUserNotificationCenter-based on watch), and `WatchDataProvider` syncs metadata to the shared store for the paired phone.
   - ✅ Reminder chips in list/detail screens also use `bell.fill` + device SF Symbols with the same neutral styling as iOS.
4. **Data plumbing**
   - ✅ `ActivityReminderMetadataStore` persists records in the private database + custom zone.
   - ✅ Owned + shared refresh flows now fetch reminder metadata before caching, the watch data provider overlays the same payload when syncing snapshots, the `CKFetchRecordsOperation` fetch awaits completion, and `LocalCacheService.replaceCaree` copies reminder fields when rebuilding the cache so list/detail views retain the bell state after pull-to-refresh.
5. **Lifecycle hooks**
   - ✅ Saving/deleting activities schedules/cancels reminders and upserts/deletes metadata records.
   - ⏳ Run a regression/soak pass after the overlay fetch to ensure edits/deletes from either device keep metadata in sync (especially when offline then reconnecting).
   - Optional future enhancement: cleanup overdue reminders or reschedule logic.

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
### Current Progress
- Branch `feat/reminders-phase1` contains the implemented EventKit scheduler, reminder metadata models, iOS UI, and metadata store.
- Metadata records successfully save to the private custom zone when reminders are scheduled; logs confirm creation.
- Reminder indicators render correctly immediately after scheduling.

### Known Issues
1. **watchOS reminder QA** – Need an end-to-end pass on hardware to ensure Track/Edit/Delete flows schedule/cancel the local notification, persist metadata, and keep indicators in sync after cache refreshes.
2. **watch permission guidance** – When `UNUserNotificationCenter` reports `.denied`, surface the same Settings hand-off we added on iOS so the toggle reverts gracefully.
3. **Docs & screenshots** – README/docs still need new copy + imagery before releasing reminders publicly.

### Next Actions
1. **Watch wiring + QA**
   - iOS overlay + reminder QA complete; replicate those validation steps on watch hardware (owned + shared carees) to confirm metadata sync back to iPhone, including bell/device glyphs in list/detail views.
   - Harden denial flows by guiding users to watch Settings when authorization fails (mirroring the new logging in `ReminderScheduler`).
   - Capture logs from `ReminderScheduler`’s new authorization instrumentation to verify status transitions.
2. **Docs & screenshots prep**
   - ✅ `docs/how-to/set-reminders.md` now covers iOS + watch reminder creation with populated screenshots.
   - ✅ README.md and docs/index.md now link to the reminder how-to so users can find it quickly.
   - Once watch QA wraps, capture any remaining screenshots (e.g., bell indicators, Settings prompts) and update README/docs feature blurbs if we need additional visuals.

Testing:
- ✅ Unit tests for `ReminderScheduler` permission branching now live (`CareKeeperTests/ReminderSchedulerTests.swift`) using the injectable initializer to avoid UI prompts.
- ⏳ Manual verification on device + watch once the overlay QA pass is scheduled; capture test cases covering edit/delete paths and denied-permission flows.

Once the outstanding items above are complete, Phase 1 can be considered feature-complete and we can move on to Phase 3 documentation/screenshots.

## Potential Improvements (Future Work)
1. **ActivityType `hasReminders` flag** – gate the reminder UI by activity type to reduce watch UI clutter. Requires CloudKit schema update + snapshot/service changes. Capture as a future enhancement rather than current scope.
2. **Cross-device auto scheduling** – when iOS receives a watch-originated reminder metadata update (or vice versa), consider auto-creating/canceling the local reminder so actions propagate between devices.
