# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CareKeeper is an iOS/watchOS app for tracking care activities using SwiftUI and Core Data with CloudKit sharing. The app manages "Carees" (care recipients), their behaviors, and activity tracking with location support.

## Documentation

This file (CLAUDE.md) provides quick reference for development. Additional technical documentation:

- **Architecture Decision Records (ADRs)**: `/technical/adr/` - Key architectural decisions with context and rationale
- **Specifications**: `/technical/specs/` - Detailed feature specifications (CloudKit migration, push notifications)
- **Troubleshooting**: `/technical/troubleshooting/` - Debugging guides and diagnostics
- **Retrospectives**: `/technical/retrospectives/` - Post-implementation reviews and refactoring plans

User-facing documentation (tutorials, how-tos, reference) is in `/docs/` (MkDocs site).

## Development Commands

### Building and Running
- Open `CareKeeper.xcodeproj` in Xcode
- Build and run the iOS app: select "CareKeeper" scheme and target device
- Build and run the watchOS app: select "CareKeeper Watch App" scheme and Apple Watch simulator

### Testing
- Run tests through Xcode Test Navigator or Cmd+U
- No specific test scripts configured - uses standard Xcode testing

## Code Architecture

### SwiftData Model
The app uses SwiftData with three main model entities:
- **Caree**: Care recipients with name, list order, and optional photo (Data)
- **ActivityType**: Trackable activities with icons, quantity/location configuration
- **Activity**: Individual activity instances with timestamps, optional location/quantity

### Key Components

#### Persistence Layer
- `ModelContainer`: SwiftData container with app group sharing
- Configured in app initialization with fallback to in-memory storage on error
- Supports CloudKit sync via ModelConfiguration (Phase 2)
- App group: `group.com.kareemf.CareKeeper` for iOS/watchOS data sharing

#### Error Handling
- **AppError**: Centralized error enum conforming to LocalizedError
  - `modelContainerFailed`, `saveFailed`, `deleteFailed`
  - `locationPermissionDenied`, `locationUnavailable`
  - `invalidInput` for user input validation
- **ErrorAlert**: Reusable ViewModifier for consistent error presentation
- **LocationManager**: @Published error property for reactive error handling

#### SwiftUI Views (iOS)
- **Main App**: `CareKeeperApp.swift` - TabView with Carees tab
- **Caree Management**: `CareeListView`, `CareeDetailView`, `CareeEditView`
- **Activity Type Management**: `ActivityTypeEditView`, `ActivityTypeListView`
- **Activity Tracking**: `TrackActivityView`, `ActivityDetailView`, `ActivityListView`
- **Shared Components**: `ErrorAlert`, reusable view modifiers

#### SwiftUI Views (watchOS)
- **Main App**: `CareKeeperWatchApp.swift` - Minimal NavigationStack (30 lines vs iOS 250+)
- **Caree List**: Primary view with lazy loading, pull-to-refresh
- **Activity Tracking**: Full CRUD with Digital Crown input for quantity and time
  - Auto-focus on time input when custom time enabled
  - Save toast with reactive list updates
  - SF Symbol and emoji icon rendering
- **Activity Details**: Complete edit functionality (notes, quantity, time)
  - Edit mode with save toast feedback
  - Delete with confirmation dialog and toast
  - Sync state tracking (pending/syncing/synced/failed) with retry
- **Activity List**: Filtering by activity type (tap-to-cycle), reactive updates
- **Optimistic UI**: All mutations show immediately, sync in background with state tracking

#### Services
- **LocationManager**: Cross-platform location service for iOS/watchOS
  - @MainActor class with CLLocationManager integration
  - @Published properties for location, authorization, errors
  - Reactive permission handling with error propagation

- **CloudKitDataService**: Pure CloudKit CRUD operations (@MainActor ObservableObject)
  - Single source of truth for CloudKit operations
  - @Published properties: `syncStatus`, `deletionProgress`
  - Manual cascade deletion with progress tracking (0.0 to 1.0)
  - Automatic retry logic for network failures
  - Cache service integration for local persistence

- **CloudKitSharingService**: Manages CloudKit sharing and permissions
  - Share creation and participant management
  - Permission checks (owner-only caree deletion)
  - Share acceptance flow

- **CloudKitSharedRecordsService**: Fetches and monitors shared records
  - Queries shared database for carees, activity types, activities
  - Notification handling and filtering
  - Creator tracking to exclude own activities from notifications

- **LocalCacheService**: SwiftData cache for CloudKit records
  - @Published properties for `myCarees` and `sharedCarees`
  - Metadata tracking (isShared, lastSyncedAt)
  - Reactive updates via Combine publishers

- **CareeImportService**: Import from JSON backup (@MainActor ObservableObject)
  - @Published `progress` property with states: idle, reading, importing, completed, failed
  - Creates CloudKit records from exported JSON
  - Real-time progress updates for UI observability

- **UserNotificationPreferences**: Manages notification preferences
  - Global notification enable/disable toggle
  - Per-caree notification settings
  - Synced via app group UserDefaults for iOS/watchOS

- **UserNotificationService**: Handles user-facing push notifications
  - UNUserNotificationCenter wrapper
  - Permission request and management
  - Local notification presentation
  - Notification tap handling for deep linking

- **CloudKitNotificationService**: Sets up CloudKit subscriptions
  - Database subscriptions for private and shared databases
  - Silent notifications for sync coordination
  - Filters activity records for user-facing notifications

- **WatchDataProvider** (watchOS only): Snapshot-based data provider
  - Direct CloudKit communication via SelectiveCloudKitService
  - Lazy loading strategy: carees eager, activity types on-demand, activities on-demand (24h window)
  - Memory management with cache clearing (`clearUnusedCache`, `clearAllCache`) and task cancellation
  - Optimistic UI with sync state tracking (pending → syncing → synced/failed)
  - No SwiftData - uses immutable snapshots (CareeSnapshot, ActivityTypeSnapshot, ActivitySnapshot)
  - Background sync with Task.detached, restores UI on failure

- **SelectiveCloudKitService** (watchOS only): Watch-optimized CloudKit queries
  - Aggressive filtering: 24-hour activity window, 100 activities max, 50 activity types max
  - Retry logic with exponential backoff (2s, 4s, 8s) for transient errors
  - Zone discovery for shared database queries (searches all zones)
  - Lightweight count queries without loading full objects
  - Compatible with iOS SwiftData schema (sets CD_id, CD_creatorUserRecordID fields)
  - Memory monitoring with MemoryMonitor logging

### Key Patterns
- SwiftUI with `@State`, `@StateObject`, `@Environment` for state management
- SwiftData models shared between iOS and watchOS targets via project.yml
- CloudKit sync prepared (entitlements commented out until Phase 2)
- LocalizedError protocol for user-friendly error messages
- Input validation with helpful feedback messages
- Location tracking optional per ActivityType

### File Organization
- `/CareKeeper/`: Main iOS app source
  - `/App/`: App entry point and initialization
  - `/Models/`: SwiftData model entities
  - `/Views/`: Feature-organized view hierarchy
    - `/Caree/`, `/ActivityType/`, `/Activity/`
    - `/Components/`: Shared view components
  - `/Services/`: LocationManager, AppError
  - `/Preview/`: Preview data and container
- `/CareKeeper Watch App/`: watchOS-specific code
  - `/App/`, `/Views/`: Parallel structure to iOS
  - Shares Models, Services, Components from iOS via project.yml

### Development Notes
- Uses CloudKit container identifier: `iCloud.com.kareemf.CareKeeper2`
- Both iOS and watchOS apps share the same SwiftData models
- Location services integrated for activities when ActivityType.hasLocation == true
- XcodeGen project generation from `project.yml`
- Unit tests with in-memory ModelContainer for isolation

## Platform Architecture Differences

### iOS: SwiftData + CloudKit Hybrid
**Persistence**: Dual ModelContainer architecture
- **Main container**: Local-only SwiftData (no `cloudKitDatabase` — removed to prevent `PFCloudKitSerializer` assertion failures from `.none` reference actions on child records)
- **Cache container**: Local-only SwiftData for fast offline reads (used by `LocalCacheService`)
- `LocalCacheService` is the source of truth for all views; populated by `CloudKitDataService` custom fetch code

**Services**: Multi-service architecture (5+ specialized services)
- CloudKitDataService: CRUD for owned carees
- CloudKitSharedDataService: CRUD for shared carees
- LocalCacheService: SwiftData cache with debounced refresh (0.25s)
- CloudKitSharingService: Share management (UICloudSharingController)
- UserNotificationService: Push notifications with deep linking

**Loading Strategy**: Eager loading with background refresh
- All data loaded on demand
- SwiftData handles relationship traversal
- Background tasks for sync

**Data Models**: SwiftData managed objects with relationships
- `caree.activityTypes`, `caree.activities` relationships
- Mutable objects tracked by SwiftData context

### watchOS: Direct CloudKit with Snapshots
**Persistence**: No SwiftData - direct CloudKit only
- WatchDataProvider as single data source
- Direct CloudKit API calls via SelectiveCloudKitService
- No ModelContainer initialization

**Services**: Unified provider architecture
- Single WatchDataProvider manages all state
- SelectiveCloudKitService for optimized queries
- Shares logging, monitoring, preferences services with iOS

**Loading Strategy**: Lazy loading with aggressive limits
- Carees: Eager (small dataset, ~20 typical)
- Activity types: On-demand when user opens caree detail
- Activities: On-demand with 24-hour window, 100 max per caree
- Active cache clearing on view disappear

**Data Models**: Immutable snapshots, flat structure
- CareeSnapshot, ActivityTypeSnapshot, ActivitySnapshot
- No relationships - all IDs stored as UUID properties
- Prevents accidental relationship traversal

### Shared Between Platforms
**Models**: Caree, ActivityType, Activity (SwiftData definitions)
- Compiled for both targets via project.yml
- watchOS doesn't use SwiftData features, but shares type definitions

**Snapshots**: CareeSnapshot, ActivityTypeSnapshot, ActivitySnapshot
- Used by watchOS exclusively
- Could be adopted by iOS for view layer

**Services** (cross-platform):
- AppLogger, FileLogger: Logging infrastructure
- MemoryMonitor, MetricsManager: Diagnostics
- CloudKitConfig: Container and zone constants
- LocationManager: Location services (platform-adapted)
- UserNotificationPreferences: Settings synced via app group UserDefaults
- AppError: Shared error definitions

**Architecture Tradeoffs**:
- iOS: Full power, offline-first, relationship queries → Higher memory, more complex
- watchOS: Optimized, memory-conscious, explicit loading → Limited history, manual cache management

## Development Guidelines

### Git Workflow
- Make one git commit per requirement being implemented
- Use descriptive commit messages that reference the specific requirement
- Commit early and often to track progress on individual features

## CareKeeper - Project Specification

### Project Overview
**Purpose**: A fast, collaborative activity tracking app for caregivers (child care, pet care, etc.) with iOS and watchOS companions. Prioritizes quick data entry and coordination between multiple caregivers.

**Success Criteria**: Feature completeness with v1, production-ready UX polish, modern coding practices, comprehensive testing, security, and privacy.

### Implementation Approach
- **Clean rewrite** using modern iOS development practices
- Target iOS 18+ and watchOS 10+
- SwiftData + CloudKit for data persistence and sharing
- SwiftUI with latest architectural patterns
- Comprehensive unit testing with XCTest
- UI testing for critical user flows

### Data Model (SwiftData Entities)

#### Caree
- `id: UUID` (primary key)
- `name: String` (required)
- `image: Data?` (optional profile photo)
- `listOrder: Int` (for user-defined ordering)
- `dateCreated: Date`

#### ActivityType (formerly Behavior)
- `id: UUID` (primary key)
- `name: String` (required)
- `icon: String?` (emoji or SF Symbol)
- `hasQuantity: Bool = false`
- `quantityUnit: String?` (e.g., "oz", "minutes")
- `hasLocation: Bool = false`
- `listOrder: Int` (user-defined ordering)
- `careeId: UUID` (foreign key)
- `dateCreated: Date`

#### Activity
- `id: UUID` (primary key)
- `dateTime: Date` (when activity occurred)
- `notes: String?`
- `quantity: Double?` (if ActivityType.hasQuantity)
- `latitude: Double?` (if ActivityType.hasLocation)
- `longitude: Double?` (if ActivityType.hasLocation)
- `activityTypeId: UUID` (foreign key)
- `careeId: UUID` (foreign key)
- `dateCreated: Date`

### Encryption at Rest Strategy
**Infrastructure-level encryption:**
- **Local device**: iOS automatically encrypts device storage when locked
- **CloudKit sync**: Automatic encryption in transit and at rest on Apple servers
- **Core Data store**: SwiftData with `NSPersistentStoreFileProtectionKey` for additional local protection
- **Sharing compatibility**: Field-level encryption via `CKRecord.EncryptedValues` is NOT used because it's incompatible with CloudKit sharing (participants cannot decrypt owner's encrypted fields)
- **Security model**: Relies on Apple's infrastructure encryption, which is industry-standard for collaborative apps

**Note**: For truly private data that should never be shared, use `encryptedValues`. For collaborative data (this app's use case), infrastructure encryption is the correct choice.

### Why Not Field-Level Encryption?

**TL;DR**: `CKRecord.EncryptedValues` is incompatible with CloudKit sharing.

**Technical Details**:
- `encryptedValues` uses owner's private key for encryption
- Only owner's device can decrypt
- Share participants see `nil` for encrypted fields
- Designed for truly private data (passwords, tokens, etc.)

**CareKeeper's Requirements**:
- ✅ Multiple caregivers need read/write access to shared data
- ✅ Notes, locations, and names must be accessible to all participants
- ✅ Collaborative care tracking is the core feature

**Decision**: Use infrastructure-level encryption (industry standard for collaborative apps like iCloud Notes, shared reminders, etc.)

**Additional Security Measures**:
- Device encryption protects local data
- iCloud account security (2FA) protects cloud access
- Explicit share acceptance required
- Permission management (owner can revoke access)
- App-level access controls can be added (Face ID lock, etc.)

### Implementation Phases

#### Phase 0: Foundation
1. Project setup with modern architecture
2. SwiftData models and CloudKit integration
3. Basic navigation structure
4. Mock data for prototyping
5. README with setup instructions

#### Phase 1: Core Features
1. Caree management (CRUD)
2. Activity Type management
3. Activity tracking and management
4. Basic watchOS companion
5. Unit test coverage

#### Phase 2: Polish & Sharing
1. CloudKit sharing implementation
2. UI polish and animations
3. Error handling and edge cases
4. watchOS feature parity
5. UI test coverage

### Out of Scope
- Data migration from v1
- Generalized habit tracking (separate consideration)
- HIPAA compliance (separate spec)
- Multi-language support (architecture prepared with NSLocalizedString)
- Advanced analytics/reporting

### CloudKit Implementation Specification

#### Purpose & User Problem
Enable multiple caregivers to track activities for the same caree(s) across their devices. Currently, data is isolated to a single device, making coordination between caregivers impossible.

#### Success Criteria
1. **Basic Sync**: User's data automatically syncs across their own iOS/watchOS devices
2. **Sharing**: Users can share specific carees with other caregivers via share link
3. **Reliability**: Conflict resolution handles concurrent edits gracefully
4. **Privacy**: Only explicitly shared carees are accessible to other users
5. **Offline UX**: Persistent sync status indicator with manual retry

#### Implementation Phases

**Phase 2.1: Basic CloudKit Sync**
- Enable CloudKit container and entitlements
- Configure ModelContainer with CloudKit sync
- Sync status indicator component with manual retry
- Verify sync across user's devices (iOS ↔️ iOS, iOS ↔️ watchOS)
- Handle network errors and offline mode
- Test conflict resolution for concurrent edits

**Phase 2.2: CloudKit Sharing**
- Share individual Carees with other users via share link
- Invitation flow (generate share link for Messages/copy-paste)
- Accept shared carees from link
- Participant management UI (view participants, remove if owner)
- Permission implementation:
  - ✅ Participants: add/edit/delete activities and activity types, edit caree details
  - ❌ Participants: cannot delete caree (owner only)
- Handle share acceptance errors
- Sharing controls in both CareeDetailView toolbar and CareeEditView

#### Technical Details

**CloudKit Container**: `iCloud.com.kareemf.CareKeeper2`

**SwiftData Configuration**:
- Main container is local-only (no `cloudKitDatabase` parameter) — CloudKit sync handled entirely by `CloudKitDataService`
- ⚠️ Do NOT add `cloudKitDatabase: .private` to the main `ModelConfiguration`; it conflicts with `.none` reference actions on child records and causes `PFCloudKitSerializer` assertion failures

**Sync Status Component**:
- Observable service monitoring CloudKit sync state
- Three states: syncing, synced, failed
- Manual retry action
- Positioned in navigation/toolbar

**Data Model**:
- Caree is the sharable root entity
- ActivityType and Activity cascade from Caree
- Sharing a Caree includes all its ActivityTypes and Activities

**Critical Schema Fields** (required for iOS/watchOS compatibility):
- `CD_id`: String UUID (required by SwiftData CloudKit integration)
  - iOS SwiftData auto-generates this field
  - watchOS SelectiveCloudKitService must explicitly set: `record["CD_id"] = activity.id.uuidString`
  - Without this field, iOS cannot import watch-created activities
- `CD_creatorUserRecordID`: String (for notification filtering and attribution)
  - Set using: `CKRecord.ID(recordName: CKCurrentUserDefaultName).recordName`
  - Used to exclude own activities from notifications
  - Enables proper attribution in shared caree scenarios

#### CloudKit Parent Reference Constraints

**Critical Requirement**: CloudKit requires parent references in sharing hierarchies to use `CKRecord.ReferenceAction.none` instead of `.deleteSelf`. This is a CloudKit constraint for records that participate in sharing.

**Implementation**:
```swift
// In CloudKitRecordConverter.swift
record.parent = CKRecord.Reference(record: parentCaree, action: .none)
```

**Consequences**:
- Manual cascade deletion is required when deleting a Caree
- CloudKit will not automatically delete child records (ActivityTypes and Activities)
- Must query and delete children explicitly in correct order:
  1. Query and delete all Activities for each ActivityType
  2. Delete all ActivityTypes for the Caree
  3. Finally delete the Caree record

**Progress Tracking**:
- `CloudKitDataService.deletionProgress` provides real-time progress (0.0 to 1.0)
- UI displays progress overlay during deletion
- Progress breakdown:
  - 0.0-0.2: Querying ActivityTypes
  - 0.2-0.6: Deleting Activities
  - 0.6-0.8: Deleting ActivityTypes
  - 0.8-0.9: Deleting Caree
  - 0.9-1.0: Cache cleanup

**Error**: "Record delete would violate validating reference"
- Occurs when trying to delete parent before children
- Solution: Implemented manual cascade deletion in `CloudKitDataService.deleteCaree()`

#### Push Notifications Configuration

**Entitlements Required**:
- `aps-environment` must be set in entitlements file
- Values: `development` (for development builds) or `production` (for App Store)
- Location: `CareKeeper.entitlements` and `CareKeeper Watch App.entitlements`

```xml
<key>aps-environment</key>
<string>development</string>
```

**Error**: "no valid 'aps-environment' entitlement string found for application"
- Occurs when registering for remote notifications without proper entitlement
- Solution: Add aps-environment key to entitlements file

**CloudKit Subscriptions**:
- **Database Subscriptions**: Monitor all changes in a database (private or shared)
  - Used for: General database change notifications
  - Silent notifications only (no user permission required)
  - Implementation: `CKDatabaseSubscription`

- **Query Subscriptions**: Monitor specific record types with predicates
  - **NOT allowed in shared database** (CloudKit limitation)
  - Used for: Activity notifications in private database
  - Can trigger user-facing notifications (requires permission)
  - Implementation: `CKQuerySubscription`

**Notification Strategy**:
1. Database subscription for shared database (catches all changes)
2. Filter for CD_Activity records in notification handler
3. Check `CD_creatorUserRecordID` to exclude own activities
4. Respect per-caree notification preferences

#### Out of Scope (CloudKit)
- Granular permissions (read-only access)
- Share activity history/analytics
- Custom offline conflict resolution UI (rely on CloudKit defaults)
- Share multiple carees at once
- Mock CloudKit for testing (future enhancement)

### Implementation Status

#### Phase 0: Foundation ✅ COMPLETE
- Project setup with XcodeGen and modern architecture
- SwiftData models (Caree, ActivityType, Activity)
- Basic navigation structure (TabView, NavigationStack)
- Preview data for prototyping

#### Phase 1: Core Features ✅ COMPLETE
- Caree management (CRUD) with photo picker
- Activity Type management (CRUD) with icons and configuration
- Activity tracking with location and quantity support
- Basic watchOS companion with Digital Crown input
- Unit test coverage (40 tests across all models)

#### Phase 2: Polish & Sharing 🔄 IN PROGRESS
**Completed:**
- ✅ Error handling infrastructure (AppError, ErrorAlert view modifier)
  - ✅ Replaced print() debugging with user-facing error alerts
  - ✅ Input validation with user feedback (quantity, name validation)
  - ✅ Location error handling and permission management

- ✅ Phase 2.1: Basic CloudKit Sync
  - ✅ CloudKit entitlements and ModelContainer configuration
  - ✅ Made all model properties CloudKit-compatible with default values
  - ✅ Updated all views to handle optional relationships
  - ✅ Sync status indicator with manual retry
  - ✅ Network monitoring and iCloud account status detection
  - ✅ ModelContainer successfully initializes with CloudKit enabled
  - ✅ Cross-device sync verification (requires device testing with signed-in iCloud account)
  - ⚠️ Conflict resolution testing (relies on CloudKit automatic handling)

- ✅ Phase 2.2: CloudKit Sharing
  - ✅ CloudKitSharingService for share management
  - ✅ Share button UI in CareeDetailView and CareeEditView
  - ✅ CloudSharingView (iOS-only UICloudSharingController wrapper)
  - ✅ ShareParticipantsView for participant management
  - ✅ Share acceptance flow via URL handling
  - ✅ Permission checks (owner-only caree deletion)
  - ⚠️ Full sharing flow testing (requires real CloudKit setup and multiple iCloud accounts)

- ✅ UI polish: animations, transitions, loading states
  - ✅ Smooth view transitions with fade and scale effects
  - ✅ List operation animations (add/delete/move)
  - ✅ Empty state animations with symbol effects
  - ✅ Activity tracking UX polish with loading states
  - ✅ Form validation feedback with shake animations

- ✅ UI test coverage for critical user flows
  - ✅ CareeManagementUITests (CRUD operations)
  - ✅ ActivityTypeUITests (type configuration)
  - ✅ ActivityTrackingUITests (activity tracking flows)
  - ⚠️ Some tests have timing/interaction flakiness (common XCTest UI testing challenges)

- ✅ watchOS widget/complication support
  - ✅ WidgetKit extension target
  - ✅ Four complication families (circular, rectangular, inline, corner)
  - ✅ Timeline provider with 15-minute updates
  - ✅ Display today's activity count
  - ✅ App group sharing for data access

- ✅ watchOS feature parity (COMPLETE)
  - ✅ ActivityListView with filtering by activity type (tap-to-cycle filter)
  - ✅ Full edit capability in ActivityDetailView (notes, quantity, dateTime)
  - ✅ Delete functionality with confirmation dialog and success toast
  - ✅ Save functionality with success toast and reactive list updates
  - ✅ Auto-focus on time input when entering edit mode
  - ✅ Digital Crown integration for both quantity and time editing
  - ✅ Symbol rendering (SF Symbols and emoji support via ActivityTypeIconView)
  - ✅ Optimistic UI with background sync and retry logic
  - ✅ Sync state tracking (pending/syncing/synced/failed) with manual retry
  - ✅ Memory management with cache clearing and task cancellation
  - ✅ Navigation from CareeDetailView to full activity list
  - ✅ watchOS-specific UI adaptations (Digital Crown, no Menu, focusable controls)

- ✅ Shared Caree Full CRUD Support
  - ✅ Fetch ActivityTypes and Activities from CloudKit shared database
  - ✅ Enable non-owners to create ActivityTypes on shared carees
  - ✅ Enable non-owners to track Activities on shared carees
  - ✅ Enable non-owners to edit Activities on shared carees (iOS and watchOS)
  - ✅ Enable non-owners to delete Activities on shared carees (iOS and watchOS)
  - ✅ CloudKitSharedRecordsService enhancement: queries CD_ActivityType and CD_Activity records
  - ✅ CloudKitSharedDataService: complete CRUD operations for shared ActivityTypes/Activities
  - ✅ View routing: automatic detection and CloudKit vs SwiftData routing
  - ✅ Cross-platform: implemented on both iOS and watchOS

- ✅ Push Notifications for Shared Activities
  - ✅ UserNotificationPreferences service for notification settings
  - ✅ UserNotificationService for UNUserNotificationCenter integration
  - ✅ CloudKit query subscription for CD_Activity records with alerts
  - ✅ Notification handling in CloudKitSharedRecordsService
  - ✅ Creator tracking (CD_creatorUserRecordID) to filter own activities
  - ✅ Per-caree notification toggles in CareeDetailView (iOS & watchOS)
  - ✅ Permission request flow with Settings deep link (iOS)
  - ✅ Notification tap handling for deep linking to activity detail
  - ✅ Preferences synced via app group UserDefaults
  - ⚠️ End-to-end testing requires physical devices and multiple iCloud accounts

**Implementation Complete:**
Phase 2.2 CloudKit Sharing is now fully functional with complete CRUD support for shared carees, activity types, and activities across both iOS and watchOS platforms. Push notifications enable real-time coordination between caregivers when activities are logged on shared carees.

## Troubleshooting Guide

### CloudKit Issues

#### "Parent references must be CKReferenceActionNone"
**Cause**: Using `.deleteSelf` action for parent references in sharing hierarchies
**Solution**: Change all parent references to use `.none` action
**Files**: `CloudKitRecordConverter.swift`
```swift
// Incorrect
record.parent = CKRecord.Reference(record: parentCaree, action: .deleteSelf)

// Correct
record.parent = CKRecord.Reference(record: parentCaree, action: .none)
```

#### "Record delete would violate validating reference"
**Cause**: Attempting to delete parent record before children when using `.none` action
**Solution**: Implement manual cascade deletion
**Files**: `CloudKitDataService.swift` - `deleteCaree()` method
**Order**: Delete Activities → Delete ActivityTypes → Delete Caree

#### "Did not find record type: cloudkit.share"
**Cause**: Trying to create query subscription for system record types
**Solution**: Use `CKDatabaseSubscription` instead of `CKQuerySubscription`
**Files**: `CloudKitNotificationService.swift`

#### "Subscription evaluation type not allowed in shared database"
**Cause**: Query subscriptions are not supported in shared CloudKit databases
**Solution**: Use database subscription and filter in notification handler
**Files**: `CloudKitNotificationService.swift`, `CloudKitSharedRecordsService.swift`

#### "invalid attempt to set value type ASSETID for field 'CD_image'"
**Cause**: Schema field type mismatch (BYTES vs ASSETID/CKAsset)
**Solution**: Use separate field for asset type (e.g., `CD_image_ckAsset`)
**Note**: CloudKit schema field types cannot be changed after deployment

### Push Notification Issues

#### "no valid 'aps-environment' entitlement string found"
**Cause**: Missing aps-environment key in entitlements
**Solution**: Add to both iOS and watchOS entitlements files
```xml
<key>aps-environment</key>
<string>development</string>
```
**Files**: `CareKeeper.entitlements`, `CareKeeper Watch App.entitlements`

#### Notifications not appearing for shared activities
**Checklist**:
1. Verify user has granted notification permissions
2. Check per-caree notification settings in `UserNotificationPreferences`
3. Verify `CD_creatorUserRecordID` is set correctly (filters own activities)
4. Confirm database subscription is active in shared database
5. Check notification handler filtering logic in `CloudKitSharedRecordsService`

### Data Sync Issues

#### Watch-created activities not syncing to iOS
**Symptoms**:
- Activities created on watchOS don't appear in iOS app
- iOS logs show: "Missing required field 'CD_id or CD_dateTime'"
- iOS logs show: "Record identifier should be a string"
- CoreData+CloudKit errors: NSCocoaErrorDomain Code=134420

**Root Cause**: Missing required CloudKit fields that iOS SwiftData expects

**Solution**: Implemented in commits 957775c and 57a42b4
- SelectiveCloudKitService now sets `CD_id` field: `record["CD_id"] = activity.id.uuidString`
- SelectiveCloudKitService now sets `CD_creatorUserRecordID` field
- Both fields are required for iOS SwiftData CloudKit integration

**Verification**:
1. Check CloudKit Dashboard that new watch-created activities have `CD_id` as String field
2. Check that `CD_creatorUserRecordID` is set to current user's record ID
3. Pull to refresh on iOS CareeDetail or ActivityList
4. New activities should now appear

**Important Note**: Activities created before these fixes (prior to commits 957775c, 57a42b4) won't sync as they're missing required fields. These old records cannot be retroactively fixed and should be re-created if needed.

#### CareeList not updating after creation
**Cause**: View using computed property instead of observable state
**Solution**: Use `@State` with publisher observation
**Pattern**:
```swift
@State private var allCarees: [Caree] = []

.onReceive(cacheService?.$myCarees ?? Just([]).eraseToAnyPublisher()) { _ in
    updateAllCarees()
}
```
**Files**: `CareeListView.swift` (iOS and watchOS)

#### Import progress stuck at "Reading file..."
**Cause**: `CareeImportService` not observable, progress not updating view
**Solution**:
1. Make service conform to `ObservableObject`
2. Create as `@State` property in view
3. Observe service's `$progress` publisher
**Files**: `CareeImportService.swift`, `CareeListView.swift`

### Provisioning Issues

#### "Provisioning profile doesn't match entitlements"
**Cause**: New CloudKit container not synced with Xcode/Apple servers
**Solution**:
1. Toggle automatic signing off and on in Xcode
2. Download manual provisioning profiles
3. Clean build folder (Cmd+Shift+K)
4. Restart Xcode if needed

### Performance Considerations

#### Slow Caree deletion
**Expected**: Manual cascade deletion takes time for carees with many activities
**UX Solution**: Progress indicator shows real-time progress
**Optimization**: Deletions happen in batches where possible

#### Import taking long time
**Expected**: Creating CloudKit records individually with verification
**UX Solution**: `ImportProgressView` shows current/total records
**Pattern**: Import progress tracked via `CareeImportService.$progress`

### Testing Notes

#### CloudKit sharing requires real devices
**Limitation**: CloudKit sharing cannot be fully tested in simulator
**Requirements**:
- Two physical devices with different iCloud accounts
- Both devices signed into iCloud
- App installed with valid provisioning profile

#### UI test flakiness
**Known Issue**: Some XCTest UI tests have timing issues
**Workaround**: Increase wait times, add explicit synchronization
**Files**: `CareeManagementUITests.swift`, `ActivityTrackingUITests.swift`

### Debugging Tools

#### CloudKit Dashboard
**URL**: https://icloud.developer.apple.com/dashboard
**Use cases**:
- Verify record schema
- Check subscription status
- Query records directly
- Monitor API usage

#### Console.app Logging
**Filter**: Process: CareKeeper or CareKeeper Watch App
**Categories**: CloudKit, Notifications
**Pattern**: All logs use `AppLogger` with consistent prefixes

#### Network Link Conditioner
**Use**: Test offline behavior and sync retries
**Location**: Additional Tools for Xcode
**Test scenarios**: No network, slow network, packet loss
