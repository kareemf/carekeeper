# How to Schedule Reminders

CareKeeper lets you attach personal reminders to specific activities so you get a nudge when it’s time to follow up. On iPhone/iPad, a true Reminder gets created in Apple’s Reminders app (which syncs through iCloud to your other Apple devices signed in with the same Apple ID). On Apple Watch we schedule an on-device notification. Behind the scenes we keep the metadata in sync, so creating or editing a reminder on either device automatically creates/updates the counterpart on the other device—no need to manage them separately.

## iPhone/iPad

1. Open a caree and tap an activity type.
2. Toggle **Set Reminder**.
3. Pick a future date/time (up to 7 days out).
4. Save the activity. You’ll see a bell icon next to any activity that has a pending reminder.

> If you haven’t granted Reminders access before, iOS will request permission when you toggle **Set Reminder**. If you dismiss the prompt or previously denied access, you’ll see an error with an **Open Settings** shortcut—enable Reminders access there, then retry.

## Apple Watch

1. Open the Track Activity view.
2. Toggle **Set Reminder**.
3. Use the Digital Crown to choose the number of minutes in the future (up to 24 hours).
4. Save the activity. The list and detail screens show a bell with either `📱` or `⌚️` indicating the device you used most recently; CareKeeper still schedules the matching reminder/notification on your other device automatically.

> watchOS relies on Notification permission. If the toggle shows an error, open the Settings app on your watch (or the Watch app on iPhone) and enable **Notifications → CareKeeper → Allow Notifications** before retrying.

## Managing Existing Reminders

- Edit the activity on whatever device is convenient. Changes made on iPhone update the Reminders entry and push the same change (date/time, notes) to the matching watch notification, and vice versa.
- Toggling the reminder off on either device deletes the reminder/notification everywhere. You no longer need to toggle both devices.
- Deleting the activity removes all reminders/notifications tied to it on your devices.

## Screenshots

<div class="app-overview-grid">
  <img src="/screenshots/ios-activity-detail-view-showing-reminder-toggle-and-date-picker.PNG" alt="iOS Activity detail view showing reminder toggle and date picker" />
  <img src="/screenshots/watchos-track-activity-view-showing-reminder-toggle-with-minutes-from-now-crown-control.PNG" alt="watchOS Track Activity view showing reminder toggle with minutes-from-now crown control" />
</div>

<!-- ![iOS Activity detail view showing reminder toggle and date picker](../screenshots/ios-activity-detail-view-showing-reminder-toggle-and-date-picker.PNG){: .doc-screenshot } -->
<!-- ![watchOS Track Activity view showing reminder toggle with minutes-from-now crown control](../screenshots/watchos-track-activity-view-showing-reminder-toggle-with-minutes-from-now-crown-control.PNG){: .doc-screenshot } -->
