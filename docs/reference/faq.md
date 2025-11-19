# Frequently Asked Questions

Common questions about CareKeeper, organized by topic.

## General

### What is CareKeeper?

CareKeeper is a fast, collaborative activity tracking app for iOS and watchOS. It helps multiple caregivers coordinate care for children, pets, or anyone who needs support by tracking activities like feeding, sleep, and more.

---

### How much does CareKeeper cost?

**Pricing information will be here when app is released.**

Current development status: Pre-release

---

### What devices are supported?

**iOS:**
- iPhone running iOS 18.0 or later
- iPad running iPadOS 18.0 or later

**watchOS:**
- Apple Watch running watchOS 10.0 or later

**Not supported:**
- Android devices
- Windows/Mac desktop apps (no web version)

---

### Is an internet connection required?

**Mostly yes, with offline support:**

✅ **Works offline:**
- Track activities (saved locally)
- View recently loaded data
- Edit activities

❌ **Requires internet:**
- Initial sync after install
- Sharing carees
- Syncing between devices
- Accepting shares
- Push notifications

Activities tracked offline will sync automatically when you reconnect.

---

### Is iCloud required?

**Yes.** CareKeeper requires an iCloud account for:
- Syncing between your devices
- Sharing with other caregivers
- Backup and recovery

You must be signed into iCloud in iOS Settings.

---

## Features & Capabilities

### Can I use CareKeeper without sharing?

**Yes!** Sharing is completely optional. You can:
- Track activities just for yourself
- Keep all carees private
- Sync only between your own devices

Sharing is only needed if you want to collaborate with other caregivers.

---

### How many carees can I have?

**Unlimited.** Create as many carees as you need:
- Multiple children
- Multiple pets
- Family members
- Yourself (personal health tracking)

---

### How many activity types per caree?

**Unlimited** on iPhone.

**Practical limit** on Apple Watch:
- ~50 activity types per caree (performance optimization)
- More activity types = slower watch app

---

### Can I track historical data?

**Yes.** Use the custom date/time picker when tracking:
1. Tap the activity type
2. Tap the date/time field
3. Select past date and time
4. Complete and save

You can backfill data from weeks or months ago.

---

### Can I edit or delete activities?

**Yes, both:**

**Edit:**
- Swipe left on activity (iOS)
- Tap activity > Edit (watchOS)
- Change quantity, time, notes, location

**Delete:**
- Swipe left > Delete (iOS)
- Tap activity > Delete Activity (watchOS)
- Confirmation required

---

### How do reminders work across my devices?

- **iPhone/iPad** – CareKeeper saves a reminder to Apple’s Reminders app. That reminder syncs through iCloud like any other reminder tied to your Apple ID.
- **Apple Watch** – CareKeeper schedules a local notification (not an EKReminder). It’s delivered only on that watch.
- **Cross-device syncing** – When you schedule or edit a reminder on either device, CareKeeper stores the metadata in CloudKit and automatically creates/updates the matching reminder/notification on your other device. There’s no need to toggle both manually.
- The bell indicator shows which device you interacted with most recently (`📱` for phone, `⌚️` for watch), but the reminder exists on both.
- Toggling the reminder off or deleting the activity removes the reminder/notification on all of your devices.

See [How to Schedule Reminders](../how-to/set-reminders.md) for a step-by-step walkthrough.

---

### Can I export my data?

**Yes.** Export to JSON format:
- All data or single caree
- Includes caree, activity types, activities
- Human-readable and machine-parseable
- Import back into CareKeeper or analyze externally

See [How to Export Data](../how-to/export-data.md).

---

### Does CareKeeper integrate with Apple Health?

**Not currently.** Apple Health integration is under consideration for future versions.

---

### Can I create custom reports or charts?

**Not in the app.** CareKeeper focuses on fast tracking, not analytics.

For custom analysis:
1. Export data to JSON
2. Import into Excel, Google Sheets, or custom scripts
3. Create your own charts and reports

---

## Collaboration & Sharing

### How does sharing work?

1. **You share a caree** via share link (Messages, Mail, etc.)
2. **Recipient taps link** and accepts share
3. **Both have access** to caree, activity types, and activities
4. **Changes sync** automatically via iCloud
5. **Everyone can track** activities and see updates

See [How to Share a Caree](../how-to/share-caree.md).

---

### What can shared participants do?

**Participants can:**
- ✅ View all activities and activity types
- ✅ Track new activities
- ✅ Edit existing activities
- ✅ Delete activities
- ✅ Create new activity types
- ✅ Edit activity types
- ✅ Edit caree details (name, photo)
- ✅ Leave the share voluntarily

**Participants cannot:**
- ❌ Delete the caree entirely (owner only)
- ❌ Remove other participants (owner only)
- ❌ Stop sharing (owner only)

---

### Can I have read-only participants?

**No.** All participants have equal edit access. CareKeeper is designed for trusted collaborators, not hierarchical permissions.

If you need read-only access, consider:
- Regularly exporting and sharing reports instead
- Using screen sharing to show data without granting access

---

### How many people can I share with?

**Unlimited.** Share with as many caregivers as needed:
- Both parents
- Grandparents
- Babysitters
- Day care providers
- Pet sitters
- Healthcare providers

---

### Can I share multiple carees at once?

**No.** Share each caree individually. This gives you granular control:
- Share baby with partner and grandparents
- Share dog only with roommates
- Keep personal health tracking private

---

### Can I revoke access?

**Yes (owner only):**
1. Open caree detail view
2. Tap Share button
3. Tap participant's name
4. Tap "Remove Access"
5. Confirm

Removal is immediate. The participant loses access to the caree, activity types, and activities.

---

### What happens if I delete a shared caree?

**Owner deletes:**
- Caree deleted for everyone
- All activity types and activities deleted
- All participants lose access
- Cannot be undone

**Participant leaves:**
- Caree remains for owner and other participants
- Only that participant loses access

---

## Privacy & Security

### Is my data private?

**Yes, with caveats:**

**Private from:**
- ✅ Other CareKeeper users (except those you invite)
- ✅ Third-party advertisers (no ads)
- ✅ Analytics companies (no tracking)

**Accessible by:**
- ❌ You and people you share with
- ❌ Apple (with legal warrant, but not used for ads/profiling)

See [Security & Privacy](../explanation/security-privacy.md).

---

### Is my data encrypted?

**Yes, infrastructure-level encryption:**

**On device:** AES-256 encryption when device locked

**In iCloud:** Encrypted in transit (TLS) and at rest on Apple servers

**Not end-to-end encrypted** because that would break sharing (participants couldn't decrypt your data).

This is the same model as iCloud Notes, Reminders, and shared photo albums.

---

### Can Apple see my data?

**Technically yes, but:**
- Apple doesn't access user data for advertising
- Only accessible with legal warrant
- Protected by Apple's privacy policy
- Not sold or shared with third parties

CareKeeper uses Apple's infrastructure encryption, trusting Apple's security practices.

---

### Is CareKeeper HIPAA compliant?

**No.** CareKeeper is **not** HIPAA compliant:
- No Business Associate Agreement
- No audit trails
- Infrastructure encryption (not end-to-end)
- No access logs

**Do not use** for Protected Health Information (PHI) subject to HIPAA.

**OK for:** Personal care tracking, pet care, baby care (non-regulated)

---

### What happens to my data if I uninstall?

**Data remains in iCloud:**
- Not automatically deleted
- Still accessible if you reinstall
- Synced to other devices (if any)

**To fully delete:**
1. Delete all carees in the app
2. Wait 24 hours for iCloud cleanup
3. Then uninstall app

---

### Can I use CareKeeper without iCloud?

**No.** iCloud is required for:
- Syncing between devices
- Sharing with others
- Backup and recovery

Without iCloud, CareKeeper cannot function.

---

## Technical Questions

### Why does the watch app only show 24 hours of activities?

**Memory optimization.** Apple Watch has limited memory (~30-50MB for apps). Loading full activity history would:
- Use too much memory
- Cause crashes
- Slow down the app

24 hours covers recent activities while keeping the watch app fast and reliable. View full history on iPhone if you need more history.


### Why can't I create carees on the watch?

**Intentional limitation.** Complex operations (caree creation, activity type configuration, sharing) belong on the larger iPhone screen.

The watch app focuses on speed:
- Track activities in 2 seconds
- View recent activities
- Quick edits

---

### Does CareKeeper drain battery?

**No, minimal impact.** Normal usage (<5% battery per day) includes:
- Tracking 10-20 activities
- Viewing activity lists
- Background sync

**Higher usage if:**
- Location tracking enabled for many activities
- Notifications enabled for high-frequency carees
- App left open continuously

---

### Why is sync sometimes slow?

**Possible reasons:**
- Poor network connection (use WiFi for initial sync)
- Large data set (hundreds of activities)
- CloudKit service delays (Apple's infrastructure)
- Device in Low Power Mode

**Normal speed:**
- New activity appears on other devices within 5-15 seconds
- Initial sync after install: 10-30 seconds

---

### Can I use CareKeeper on multiple iPhones?

**Yes!** Sign into the same iCloud account on both devices:
- All carees appear on both
- Activities sync between them
- Share from either device

This is useful for:
- Personal phone + work phone
- Old phone kept as backup
- iPad + iPhone

---

### Does CareKeeper work with Family Sharing?

**Not directly.** Each person needs their own iCloud account and CareKeeper installation.

**To collaborate:**
- Each family member installs CareKeeper
- One person creates carees
- Share carees via CloudKit sharing (not Family Sharing)

---

## Support

### Why aren't my activities syncing?

**Quick fixes:**
1. Check internet connection
2. Verify both devices signed into same iCloud account
3. Pull down to refresh
4. Force quit and reopen app

---

### Why can't I share a caree?

**Common causes:**
- Not the owner (participants can't share)
- Not signed into iCloud
- No internet connection

---

### How do I contact support?

**Before contacting support:**
1. Check this FAQ
2. Export your data (Settings > Export Data) as backup

**Contact methods:**
- 📧 Email: [support email when available]
- 🐛 GitHub Issues: [if open source]
- 💬 Community: [forum/Discord if available]

Include:
- iOS/watchOS version
- Device model
- Steps to reproduce issue
- Screenshots if helpful

---

## Feature Requests

### Can you add [feature]?

CareKeeper is focused on fast, collaborative tracking. Feature requests are considered based on:
- ✅ Aligns with core mission (speed, collaboration)
- ✅ Benefits majority of users
- ✅ Doesn't add significant complexity

**Likely additions:**
- iOS widgets
- Siri shortcuts
- Additional export formats
- Accessibility improvements

**Unlikely additions:**
- Android version
- Web app
- Advanced analytics (use export instead)
- Third-party integrations
- HIPAA compliance

Submit feature requests: [submission method when available]

---

### Will CareKeeper be open source?

**Under consideration.** The project may be open-sourced in the future to enable:
- Community contributions
- Transparency
- Custom forks for specific use cases

No firm timeline yet.

---

## Comparison Questions

### CareKeeper vs generic note apps?

**CareKeeper advantages:**
- ✅ Purpose-built for care tracking
- ✅ Fast entry (2-second tracking on watch)
- ✅ Structured data (quantity, location, time)
- ✅ Real-time collaboration
- ✅ Searchable and filterable

**Generic notes:**
- Flexible for any use case
- But slower, less structured, harder to collaborate

---

### CareKeeper vs spreadsheets?

**CareKeeper advantages:**
- ✅ Mobile-optimized
- ✅ Much faster entry
- ✅ Watch app support
- ✅ Real-time sync
- ✅ No setup required

**Spreadsheets:**
- Better for complex analysis
- More customization
- But clunky on mobile, slow to track

**Best of both:** Use CareKeeper for tracking, export to spreadsheet for analysis.

---

### CareKeeper vs specialized baby/pet trackers?

**CareKeeper advantages:**
- ✅ Fully customizable (any care scenario)
- ✅ True collaboration (not just "share reports")
- ✅ Privacy-focused (no ads, no account)
- ✅ Cross-category (baby + pet in one app)
- ✅ Personal reminders per device (phone/watch)

**Specialized trackers:**
- Pre-configured for specific scenarios
- May have specialized features (growth charts, vaccination reminders)
- But less flexible, often subscription-based

---

## Still Have Questions?

**Documentation:**
- [Getting Started Tutorial](../tutorials/getting-started.md)
- [How-To Guides](../how-to/track-activity.md)

**Support:**
- Email: [when available]
- GitHub: [if open source]
- Community: [if forum exists]
