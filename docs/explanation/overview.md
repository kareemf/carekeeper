# CareKeeper Overview

CareKeeper is designed to solve a common problem: coordinating care between multiple caregivers. Whether you're tracking feeding for a newborn, medications for a pet, or activities for an elderly parent, CareKeeper makes it fast and collaborative.

## The Problem

Traditional care tracking is fragmented:

**Paper logs:**
- 📝 Easy to lose or forget
- 🚫 Not accessible to other caregivers
- ⏰ Must remember to fill out later
- 📊 Hard to analyze patterns

**Generic note apps:**
- 📱 Not designed for care tracking
- 🔄 No automatic sync between caregivers
- 🏷️ No structured data (just free text)
- ⌚ Not optimized for quick mobile entry

**Spreadsheets:**
- 💻 Clunky on mobile
- 🤝 Difficult to share and collaborate
- ⚡ Too slow for moment-to-moment tracking
- 📈 Require manual setup for each use case

## The Solution

CareKeeper is purpose-built for collaborative care tracking:

### Fast Entry
- **2-second tracking** from Apple Watch
- **Optimized UI** for common tasks
- **Digital Crown** for quick quantity entry
- **Smart defaults** to minimize taps

### Real-Time Collaboration
- **iCloud sync** across all devices
- **Instant updates** when others track
- **Push notifications** for shared activities
- **No manual syncing** required

### Flexible Structure
- **Custom activity types** for any care scenario
- **Quantity tracking** (oz, mg, minutes, etc.)
- **Location tracking** for activities on the go
- **Notes** for additional context

### Privacy-Focused
- **Your data** stays in your iCloud
- **Encrypted** in transit and at rest
- **Explicit sharing** (invite-only)
- **No ads** or third-party tracking

## Core Concepts

### The Data Model

CareKeeper uses a simple three-level hierarchy:

```
Caree (Care Recipient)
├── Activity Type (What you track)
│   ├── Name & Icon
│   ├── Quantity Settings
│   └── Location Settings
└── Activities (Instances of tracking)
    ├── Date & Time
    ├── Quantity (optional)
    ├── Location (optional)
    └── Notes (optional)
```

[SCREENSHOT: Hierarchy diagram]

### Carees

**Who** you're tracking care for:
- Children (newborns, toddlers, etc.)
- Pets (dogs, cats, etc.)
- Adults (elderly parents, patients, etc.)
- Yourself (medication tracking, etc.)

You can have multiple carees and share each independently.

### Activity Types

**What** you want to track:
- Feeding (bottles, nursing, solids)
- Diaper changes
- Sleep
- Medications
- Walks
- Playtime
- Custom activities

Activity types are reusable templates—define once, use many times.

### Activities

**Instances** of tracking:
- "Fed 4 oz at 2:30 PM"
- "Changed diaper at 3:15 PM"
- "Gave medication 5mg at 8:00 AM"

Activities capture the who, what, when, and how much of care.

## Design Philosophy

### Speed Over Features

CareKeeper prioritizes **fast tracking** over comprehensive features:

✅ **Optimized:**
- One-tap tracking for simple activities
- Digital Crown for quantity entry
- Minimal screens to navigate
- Defaults to current time

❌ **Not included:**
- Complex reporting dashboards
- Statistical analysis tools
- Custom charts and graphs
- Third-party integrations

!!! note "Philosophy"
    The best tracking system is one you'll actually use. Every feature adds complexity, so we focus ruthlessly on speed and reliability.

### Collaboration Over Solo Tracking

CareKeeper is designed for **teams of caregivers**:

✅ **Collaborative:**
- Real-time sync between participants
- Equal permissions for all participants
- Notifications about others' activities
- Shared activity types and history

❌ **Not included:**
- Granular read-only permissions
- Activity attribution (who tracked what)
- Approval workflows
- Audit trails

!!! tip "Use Case"
    If you need strict control over who can do what, CareKeeper may not be the right fit. It's designed for trusted caregivers working together, not hierarchical permission systems.

### Privacy by Design

CareKeeper uses **Apple's infrastructure** for privacy:

✅ **Privacy-first:**
- Data stored in your iCloud account
- Infrastructure-level encryption
- Invite-only sharing
- No third-party analytics
- No ads or tracking

❌ **Tradeoffs:**
- Requires iCloud account
- Requires trust in Apple's infrastructure
- Not end-to-end encrypted (incompatible with sharing)
- Not HIPAA compliant (healthcare use requires special certification)

!!! info "Security Model"
    CareKeeper follows the same security model as iCloud Notes, Reminders, and shared photo albums—industry-standard for collaborative apps.

## Platform Design

### iOS: Full-Featured

The iPhone app is the **control center**:
- Create and manage carees
- Create and configure activity types
- Track activities with full options
- Share carees with other caregivers
- View complete activity history
- Export data

[SCREENSHOT: iOS app features]

### watchOS: Speed-Optimized

The Apple Watch app focuses on **quick tracking**:
- View carees and activity types
- Track activities (1-2 taps)
- Digital Crown for quantity entry
- View recent activities (48-hour window)
- Edit activities (quantity and time)

**Not on watch:**
- Creating/editing carees
- Creating activity types
- Sharing carees
- Full activity history
- Data export

[SCREENSHOT: watchOS app features]

!!! note "Intentional Limitations"
    The watch app is intentionally limited to keep it fast and memory-efficient. Complex operations belong on the larger iPhone screen.

## Use Cases

### New Parents

Track feeding, sleep, and diapers for your newborn:
- **Both parents** track from their devices
- **See patterns** (feeding frequency, sleep duration)
- **Coordinate care** ("When did you last feed her?")
- **Share with caregivers** (grandparents, babysitters)

[SCREENSHOT: Newborn tracking example]

### Pet Owners

Track feeding, walks, and medications for your pet:
- **Roommates** coordinate care responsibilities
- **Dog walkers** log walks and activities
- **Veterinarians** review medication schedules
- **Pet sitters** know what's been done

[SCREENSHOT: Pet tracking example]

### Elderly Care

Track medications, meals, and activities for aging parents:
- **Family members** share caregiving duties
- **Professional caregivers** log activities
- **Medical providers** review patterns
- **Remote monitoring** for peace of mind

[SCREENSHOT: Elderly care example]

### Chronic Condition Management

Track symptoms, medications, and treatments:
- **Personal health** tracking
- **Share with doctors** for appointments
- **Identify patterns** and triggers
- **Medication adherence** tracking

[SCREENSHOT: Health tracking example]

## Technical Architecture

### Data Storage

**Local:**
- SwiftData (Core Data successor)
- Stored in iOS app group
- Shared between iPhone and Watch

**Cloud:**
- CloudKit (Apple's iCloud database)
- Automatic background sync
- Conflict resolution built-in

[SCREENSHOT: Architecture diagram]

### Sync Strategy

**Optimistic UI:**
- Changes appear immediately on your device
- Sync happens in background
- Conflict resolution handles concurrent edits
- Retry logic for network failures

**Result:**
- ⚡ Feels instant
- 🔄 Works offline
- 🌐 Syncs when connected
- 🤝 Handles multiple editors gracefully

### Sharing Implementation

**CloudKit Sharing:**
- Apple's built-in sharing framework
- Share links via Messages, Mail, etc.
- Accept shares with one tap
- Participant management through iOS APIs

**Caree-Level Sharing:**
- Share individual carees
- All activity types and activities included
- Participants have full edit access
- Owner can remove participants

## Roadmap & Future

### Current Status

CareKeeper is **feature-complete** for version 1:
- ✅ iOS and watchOS apps
- ✅ CloudKit sync and sharing
- ✅ Custom activity types
- ✅ Quantity and location tracking
- ✅ Push notifications
- ✅ Data export

### Not Planned (Currently)

These features are intentionally **not** in scope:
- ❌ Android support
- ❌ Web app
- ❌ Third-party integrations
- ❌ Advanced analytics/reporting
- ❌ HIPAA compliance
- ❌ Custom plugins/extensions

!!! note "Focus"
    Staying focused on core features keeps the app fast, reliable, and maintainable.

### Under Consideration

Features being evaluated for future versions:
- 🤔 Widgets for iOS
- 🤔 Siri shortcuts
- 🤔 Apple Health integration
- 🤔 Custom themes
- 🤔 Accessibility improvements

## Related Topics

- [Understanding Collaboration](collaboration.md) - How sharing and sync work
- [Security & Privacy](security-privacy.md) - How your data is protected
- [Features Reference](../reference/features.md) - Complete feature list
