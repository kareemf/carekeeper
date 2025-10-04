# CareKeeper v2

A fast, collaborative activity tracking app for caregivers with iOS and watchOS companions. Built with SwiftUI and SwiftData, featuring CloudKit integration for seamless sharing between multiple caregivers.

## Features

- **Fast Activity Tracking**: Quick data entry inspired by Apple Workouts app design
- **Collaborative Care**: Share carees and activities with other caregivers via CloudKit
- **Flexible Taxonomy**: User-defined activity types with customizable attributes
- **Cross-Platform**: Native iOS and watchOS apps with shared data
- **Offline Support**: Works offline with automatic sync when connected
- **Privacy-First**: End-to-end encryption for sensitive data

## Requirements

- iOS 18.0+ / watchOS 10.0+
- Xcode 15.0+
- Swift 5.9+
- CloudKit enabled Apple ID for sync and sharing

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/carekeeper.git
cd carekeeper
```

### 2. Install XcodeGen (Optional but Recommended)

This project uses XcodeGen to manage the Xcode project file, making it easier to handle merge conflicts and project configuration.

```bash
brew install xcodegen
```

After making changes to `project.yml`, regenerate the Xcode project:

```bash
xcodegen generate
```

> **Note**: If you don't use XcodeGen, you can still use the pre-generated `.xcodeproj` file directly.

### 3. Open in Xcode

```bash
open CareKeeper.xcodeproj
```

### 4. Configure CloudKit

1. In Xcode, select your project in the navigator
2. Select the CareKeeper target
3. Go to "Signing & Capabilities" tab
4. Ensure your Apple Developer account is selected
5. Enable "CloudKit" capability
6. Select or create a CloudKit container

### 5. Build and Run

#### Build from Command Line

**iOS App:**
```bash
# Build CareKeeperV2 for iOS Simulator
xcodebuild -project CareKeeper.xcodeproj \
  -scheme CareKeeperV2 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

**watchOS App:**
```bash
# Build CareKeeperV2 Watch App for Apple Watch Simulator
xcodebuild -project CareKeeper.xcodeproj \
  -scheme "CareKeeperV2 Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)' \
  build
```

#### Install and Launch on Simulator

**iOS App:**
```bash
# Find the booted simulator
xcrun simctl list devices | grep Booted

# Uninstall existing app (if needed)
xcrun simctl uninstall booted com.kareemf.CareKeeper

# Install the app
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-iphonesimulator/CareKeeperV2.app

# Launch the app
xcrun simctl launch booted com.kareemf.CareKeeper
```

**watchOS App:**
```bash
# Boot a paired Apple Watch simulator (if not already booted)
xcrun simctl boot "Apple Watch Ultra 2 (49mm)"

# Uninstall existing app (if needed)
xcrun simctl uninstall booted com.kareemf.CareKeeper.watchkitapp

# Install the app
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-watchsimulator/CareKeeperV2\ Watch\ App.app

# Launch the app
xcrun simctl launch booted com.kareemf.CareKeeper.watchkitapp
```

#### Quick Development Workflow

**Recommended: Use the build-install-launch script** (builds, installs, and launches both iOS and watchOS apps):

```bash
./scripts/build-install-launch.sh
```

**Manual approach** (iOS app only):

```bash
# Build, install, and launch iOS app in one command
xcodebuild -project CareKeeper.xcodeproj -scheme CareKeeperV2 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build && \
xcrun simctl uninstall booted com.kareemf.CareKeeper && \
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-iphonesimulator/CareKeeperV2.app && \
xcrun simctl launch booted com.kareemf.CareKeeper
```

#### Build from Xcode

1. Open `CareKeeper.xcodeproj` in Xcode
2. Select your target device or simulator
3. Choose either "CareKeeper" (v1) or "CareKeeperV2" (v2) scheme
4. Build and run the project (⌘+R)

The app will automatically create sample data on first launch for development purposes.

> **Tip**: Use the CareKeeperV2 scheme for the latest version with SwiftData.

## Project Structure

```
CareKeeperV2/
├── App/
│   └── CareKeeperV2App.swift          # Main app entry point
├── Models/
│   ├── Caree.swift                    # Care recipient model
│   ├── ActivityType.swift             # Activity type model (formerly Behavior)
│   └── Activity.swift                 # Activity instance model
├── Views/
│   ├── ContentView.swift              # Main tab view
│   ├── Caree/                         # Caree management views
│   │   ├── CareeListView.swift
│   │   ├── CareeDetailView.swift
│   │   ├── CareeEditView.swift
│   │   └── CareeListRowView.swift
│   ├── ActivityType/                  # Activity type management
│   │   ├── ActivityTypeEditView.swift
│   │   └── ActivityTypeRowView.swift
│   ├── Activity/                      # Activity tracking and viewing
│   │   ├── TrackActivityView.swift
│   │   ├── ActivityDetailView.swift
│   │   └── ActivityRowView.swift
│   └── Sharing/                       # CloudKit sharing (Phase 2)
│       └── SharingView.swift
└── Preview/
    ├── PreviewContainer.swift         # SwiftData container for previews
    └── PreviewData.swift              # Mock data for development
```

## Data Model

### Core Entities

- **Caree**: Care recipients (children, pets, etc.)
- **ActivityType**: User-defined activity categories with configurable attributes
- **Activity**: Individual activity instances with timestamp and optional data

### Key Features

- **SwiftData Integration**: Modern Core Data replacement with better SwiftUI integration
- **CloudKit Sync**: Automatic synchronization across devices
- **Encryption**: Infrastructure-level encryption for privacy
- **Relationships**: Proper data modeling with cascading deletes

## Development Workflow

### Syncing Data Between iOS and watchOS Simulators

**Important**: iOS and watchOS simulators run in separate containers and cannot share app group data automatically. This is a simulator limitation - on physical devices, app groups work correctly.

For end-to-end testing on simulators, use the provided sync script to copy data from iOS to watchOS:

```bash
# 1. Run the iOS app and create some data (carees, activity types, etc.)
# 2. Run the watchOS app at least once to create its app group
# 3. Sync the database
./scripts/sync-ios-to-watch-sim.sh

# The script will:
# - Find booted iOS and watchOS simulators
# - Stop both apps
# - Copy the SwiftData database from iOS to watchOS
# - Provide launch commands for both apps
```

**Why this is needed**: The watchOS app is read-only for carees and activity types (these can only be created/edited on iOS). To test activity tracking on the watch, you need to first create carees and activity types on iOS, then sync the data to watchOS.

**Note**: Once CloudKit sync is enabled in Phase 2, simulators will sync automatically via iCloud and this script won't be necessary.

### Running Tests

**From Xcode:**
```bash
⌘+U  # Run all tests (unit + UI)
```

**From Command Line:**

**Unit Tests:**
```bash
# Run all unit tests
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperV2Tests

# Run specific test class
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperV2Tests/CareeTests

# Run specific test method
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperV2Tests/CareeTests/testCreateCaree
```

**UI Tests:**
```bash
# Run all UI tests
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperV2UITests

# Run specific UI test class
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperV2UITests/CareeManagementUITests

# Run both unit and UI tests
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

All tests use in-memory SwiftData containers for fast, isolated execution.

### Code Style

- Follow Apple's Swift API Design Guidelines
- Use SwiftUI declarative patterns
- Implement proper error handling
- Write comprehensive unit tests

### Git Workflow

- One commit per feature/requirement
- Descriptive commit messages
- Feature branches for major changes

## Architecture

### MVVM + SwiftUI

- **Models**: SwiftData entities with business logic
- **Views**: SwiftUI views with minimal logic
- **ViewModels**: When needed for complex state management
- **Repository Pattern**: Data access abstraction (future enhancement)

### Key Patterns

- **Dependency Injection**: For testability
- **Error Handling**: User-friendly error messages
- **Offline-First**: Local storage with cloud sync
- **Privacy by Design**: Encrypt sensitive data

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Development Phases

### ✅ Phase 0: Foundation (Completed)
- [x] Project setup with modern architecture
- [x] SwiftData models and CloudKit integration
- [x] Basic navigation structure
- [x] Mock data for prototyping
- [x] README with setup instructions

### 🚧 Phase 1: Core Features (In Progress)
- [ ] Caree management (CRUD)
- [ ] Activity Type management
- [ ] Activity tracking and management
- [ ] Basic watchOS companion
- [ ] Unit test coverage

### 📋 Phase 2: Polish & Sharing (Planned)
- [ ] CloudKit sharing implementation
- [ ] UI polish and animations
- [ ] Error handling and edge cases
- [ ] watchOS feature parity
- [ ] UI test coverage

## Security & Privacy

- **Local Encryption**: Device storage encrypted when locked
- **CloudKit Encryption**: Automatic encryption in transit and at rest
- **Field-Level Encryption**: Sensitive data (notes, personal info) uses CloudKit's encrypted fields
- **No Third-Party Analytics**: Privacy-first approach

## License

[MIT License](LICENSE) - Feel free to use this project as a foundation for your own care tracking apps.

## Support

- 📧 [Create an issue](https://github.com/your-username/carekeeper/issues) for bug reports
- 💡 [Start a discussion](https://github.com/your-username/carekeeper/discussions) for feature requests
- 📖 [Check the wiki](https://github.com/your-username/carekeeper/wiki) for detailed documentation

## Acknowledgments

- Apple's sample code for CloudKit sharing
- SwiftUI community for best practices
- Original CareKeeper v1 for requirements and user insights