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

### Core Data Model
The app uses a Core Data model (`CareKeeperCoreData.xcdatamodeld`) with four main entities:
- **Caree**: Care recipients with name, list order, and optional photo
- **Behavior**: Activities that can be tracked (with emoji icons, location enablement)
- **Activity**: Individual instances of behaviors with timestamps and optional location data
- **Photo**: Binary photo data linked to Carees

### Key Components

#### Persistence Layer
- `PersistenceController`: Main Core Data controller with CloudKit integration
- Supports both private and shared CloudKit databases for data sharing
- History tracking enabled for remote change synchronization
- Custom error handling through `ErrorHandling` and `PersistenceErrorHandling`

#### SwiftUI Views
- **Main App**: `CareKeeperApp.swift` - TabView with Carees and Sharing tabs
- **Caree Management**: `CareeListView`, `CareeDetailView`, `CareeAddView`
- **Activity Tracking**: `ActivityTrackingViewStep1/2`, `ActivityDetailView`, `ActivityListView`
- **Behavior Management**: `BehaviorDetailView`, `BehaviorListItemView`
- **Sharing**: Complete sharing system in `/Sharing/SwiftUI/` for CloudKit collaboration

#### Platform-Specific Code
- **iOS**: Full feature set with photo picker, location services, sharing UI
- **watchOS**: Simplified interface with core tracking functionality in `CareKeeper Watch App/`

#### Third-Party Integrations
- **PhotoPicker**: Custom photo selection implementation (see `PhotoPicker/README.md`)
- **CloudKit Sharing**: Based on Apple's CloudKit sharing sample code (see `Sharing/README.md`)

### Key Patterns
- Uses SwiftUI with `@StateObject` and `@ObservableObject` for state management
- Core Data entities are shared between iOS and watchOS targets
- CloudKit integration handles both private and shared data stores
- Custom error handling system for persistence and general errors
- Location tracking optional per behavior with `CLLocationManager`

### File Organization
- `/CareKeeper/`: Main iOS app source
- `/CareKeeper Watch App/`: watchOS-specific code
- `/CareKeeper/Controllers/`: Core Data and persistence logic
- `/CareKeeper/Sharing/`: CloudKit sharing implementation
- `/CareKeeper/PhotoPicker/`: Photo selection functionality
- `/CareKeeper/ActivityTracking/`: Multi-step activity entry views

### Development Notes
- Uses CloudKit container identifier: `iCloud.com.kareemf.CareKeeperCK`
- Both iOS and watchOS apps share the same Core Data model
- Location services integrated for activity tracking when enabled per behavior
- History tracking enables synchronization between devices and shared databases

## Development Guidelines

### Git Workflow
- Make one git commit per requirement being implemented
- Use descriptive commit messages that reference the specific requirement
- Commit early and often to track progress on individual features

## CareKeeper v2 - Project Specification

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

### TODO Tracking (Implementation Phase)
*This section will be updated during development to track progress on each requirement*