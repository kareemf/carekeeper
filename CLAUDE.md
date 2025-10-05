# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CareKeeper is an iOS/watchOS app for tracking care activities using SwiftUI and Core Data with CloudKit sharing. The app manages "Carees" (care recipients), their behaviors, and activity tracking with location support.

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
- **Main App**: `CareKeeperWatchApp.swift` - NavigationStack root
- **Caree List**: Primary view for selecting caree
- **Activity Tracking**: `TrackActivityView` with Digital Crown quantity input
- **Activity Details**: Basic view/delete functionality (edit pending)

#### Services
- **LocationManager**: Cross-platform location service for iOS/watchOS
  - @MainActor class with CLLocationManager integration
  - @Published properties for location, authorization, errors
  - Reactive permission handling with error propagation

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
- Uses CloudKit container identifier: `iCloud.com.kareemf.CareKeeperCloudKit`
- Both iOS and watchOS apps share the same SwiftData models
- Location services integrated for activities when ActivityType.hasLocation == true
- XcodeGen project generation from `project.yml`
- Unit tests with in-memory ModelContainer for isolation

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
**Infrastructure-level encryption (no model properties needed):**
- **Local device**: iOS automatically encrypts device storage when locked
- **CloudKit sync**: Automatic encryption in transit and at rest on Apple servers
- **Core Data store**: Configure with `NSPersistentStoreFileProtectionKey` for additional local protection
- **Sensitive fields**: Use CloudKit's `CKRecord.EncryptedValues` for notes and other sensitive data
- **CloudKit schema**: Configure field-level encryption settings for enhanced privacy

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

**CloudKit Container**: `iCloud.com.kareemf.CareKeeperCloudKit`

**SwiftData Configuration**:
- Add CloudKit option to ModelConfiguration
- Use `cloudKitDatabase: .private` for user's private data
- Use `cloudKitDatabase: .shared` for shared carees

**Sync Status Component**:
- Observable service monitoring CloudKit sync state
- Three states: syncing, synced, failed
- Manual retry action
- Positioned in navigation/toolbar

**Data Model**:
- Caree is the sharable root entity
- ActivityType and Activity cascade from Caree
- Sharing a Caree includes all its ActivityTypes and Activities

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
  - ⚠️ Cross-device sync verification (requires device testing with signed-in iCloud account)
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

**Deferred:**
- watchOS feature parity (ActivityListView, edit capability)