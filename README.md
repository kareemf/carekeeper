# CareKeeper

A simple yet flexible collaborative activity tracking app for caregivers on iOS and watchOS. Built with SwiftUI and SwiftData, featuring CloudKit integration for sharing across devices and between multiple caregivers.

## Features

- **Fast Activity Tracking**: Quick data entry inspired by Apple Workouts app design
- **Collaborative Care**: Share carees and activities with other caregivers via CloudKit
- **Flexible Taxonomy**: User-defined activity types with customizable attributes
- **Cross-Device**: Native iOS and watchOS apps with shared data and per-device reminders
- **Offline Support**: Works offline with automatic sync when connected
- **Privacy-First**: End-to-end encryption for sensitive data

## Requirements

- iOS 18.0+ / watchOS 10.0+
- Xcode 16.0+
- Swift 5.9+
- CloudKit enabled Apple ID for sync and sharing

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/kareemf/carekeeper.git
cd carekeeper
```

### 2. Install Required Tooling

This project relies on a few CLI tools for consistent builds and linting:

```bash
brew install git-secrets xcodegen swiftformat swiftlint
```

- **git-secrets** prevents accidental commits of credentials/keys.
- **xcodegen** regenerates the Xcode project from `project.yml`.
- **swiftformat** (lint mode) enforces formatting; run `swiftformat .` to auto-fix.
- **swiftlint** enforces Swift style rules.

After updating `project.yml`, regenerate the project with:

```bash
xcodegen generate
```

> **Note**: If you don't use XcodeGen, you can still use the pre-generated `.xcodeproj` file directly, but any project file changes should be made through `project.yml`.

### 3. Configure Git Hooks

This project includes Git hooks that run checks before every commit:

1. `swiftformat` — auto-formats tracked files, re-stages the changes, then verifies formatting via lint mode.
2. `swiftlint --strict` — enforces Swift style rules.
3. `git-secrets` — prevents accidental commits of credentials/keys.
4. `xcodegen` — regenerates the Xcode project to keep it aligned with `project.yml`.

Then point Git at the repo-local hooks directory:

```bash
git config core.hooksPath .githooks
```

The pre-commit hook will fail (with actionable messaging) if any tool is missing or surfaces issues. Fix them (e.g., run `swiftformat .`, resolve lint warnings, rerun XcodeGen) and reattempt the commit. Formatting fixes performed by the hook are automatically staged, so you can simply re-run your commit afterward.

### 4. Create `Config.plist`

Runtime CloudKit/App Group identifiers now live in `CareKeeper/Shared/Config.plist`. A template ships in the repo; copy and customize it before building:

```bash
cp CareKeeper/Shared/Config.default.plist CareKeeper/Shared/Config.plist
```

or generate it from environment variables:

```bash
CLOUDKIT_CONTAINER_ID="iCloud.com.example.CareKeeper" \
APP_GROUP_IDENTIFIER="group.com.example.CareKeeper" \
ZONE_NAME="com.example.carekeeper.zone" \
./scripts/ensure-config.sh
```

`Config.plist` is git-ignored so you can safely store the real values locally. The keys are:

- `CLOUDKIT_CONTAINER_ID` – CloudKit container (e.g., `iCloud.com.kareemf.CareKeeper2`)
- `APP_GROUP_IDENTIFIER` – shared app group for iOS/watchOS
- `ZONE_NAME` – custom zone name (defaults to `com.example.carekeeper.zone` if omitted)

**Xcode Cloud / other CI:** add the command above as a pre-build script and expose the three environment variables in your CI configuration. The provided GitHub Actions workflow already does this.

### 5. Open in Xcode

```bash
open CareKeeper.xcodeproj
```

### 6. Configure CloudKit

1. In Xcode, select your project in the navigator
2. Select the CareKeeper target
3. Go to "Signing & Capabilities" tab
4. Ensure your Apple Developer account is selected
5. Enable "CloudKit" capability
6. Select or create a CloudKit container

### 7. Build and Run

#### Build from Command Line

##### iOS App
```bash
# Build CareKeeper for iOS Simulator
xcodebuild -project CareKeeper.xcodeproj \
  -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build
```

##### watchOS App
```bash
# Build CareKeeper Watch App for Apple Watch Simulator
xcodebuild -project CareKeeper.xcodeproj \
  -scheme "CareKeeper Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 2 (49mm)' \
  build
```

#### Install and Launch on Simulator

##### iOS App
```bash
# Find the booted simulator
xcrun simctl list devices | grep Booted

# Uninstall existing app (if needed)
xcrun simctl uninstall booted com.kareemf.CareKeeper

# Install the app
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-iphonesimulator/CareKeeper.app

# Launch the app
xcrun simctl launch booted com.kareemf.CareKeeper
```

##### watchOS App
```bash
# Boot a paired Apple Watch simulator (if not already booted)
xcrun simctl boot "Apple Watch Ultra 2 (49mm)"

# Uninstall existing app (if needed)
xcrun simctl uninstall booted com.kareemf.CareKeeper.watchkitapp

# Install the app
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-watchsimulator/CareKeeper\ Watch\ App.app

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
xcodebuild -project CareKeeper.xcodeproj -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build && \
xcrun simctl uninstall booted com.kareemf.CareKeeper && \
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/CareKeeper-*/Build/Products/Debug-iphonesimulator/CareKeeper.app && \
xcrun simctl launch booted com.kareemf.CareKeeper
```

## Continuous Integration

Every push and pull request triggers `.github/workflows/ci.yml`, which runs:

1. `swiftformat --lint .`
2. `swiftlint --strict`
3. `git secrets --scan`
4. `gitleaks detect --no-banner --redact`
5. `trufflehog filesystem --no-update --fail --only-verified --directory .`
6. `xcodebuild -scheme CareKeeper -project CareKeeper.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16 Pro' clean build test`

You can mirror the pipeline locally by running the commands above (after installing the required tooling).

#### Build from Xcode

1. Open `CareKeeper.xcodeproj` in Xcode
2. Select your target device or simulator
3. Choose the "CareKeeper" scheme
4. Build and run the project (⌘+R)

The app will automatically create sample data on first launch for development purposes.

## Project Structure

```
CareKeeper/
├── App/
│   └── CareKeeperApp.swift            # Main app entry point
├── Models/
│   ├── Caree.swift                    # Care recipient model
│   ├── ActivityType.swift             # Activity type model
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
│   └── Sharing/                       # CloudKit sharing
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

### Tech Features

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
  -only-testing:CareKeeperTests

# Run specific test class
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperTests/CareeTests

# Run specific test method
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperTests/CareeTests/testCreateCaree
```

**UI Tests:**
```bash
# Run all UI tests
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperUITests

# Run specific UI test class
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CareKeeperUITests/CareeManagementUITests

# Run both unit and UI tests
xcodebuild test -scheme CareKeeper \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

All tests use in-memory SwiftData containers for fast, isolated execution.

### Code Style

- Follow Apple's Swift API Design Guidelines
- Use SwiftUI declarative patterns
- Implement proper error handling

### Git Workflow

- One commit per feature/requirement
- Descriptive commit messages
- Feature branches for major changes

## Documentation

CareKeeper includes documentation for both developers and users.

### For Developers

**Technical Documentation** (in `/technical/`):
- **ADRs** (`technical/adr/`): Architecture Decision Records documenting key design choices
- **Specifications** (`technical/specs/`): Detailed feature specifications (CloudKit migration, push notifications)
- **Troubleshooting** (`technical/troubleshooting/`): Debugging guides and diagnostics
- **Retrospectives** (`technical/retrospectives/`): Post-implementation reviews and refactoring plans

### For Users

**User Documentation** (powered by MkDocs Material):

The user-facing documentation follows the [Diátaxis](https://diataxis.fr) framework. The site includes:
- **Tutorials**: Step-by-step guides for getting started
- **How-To Guides**: Task-oriented instructions
- **Explanations**: Conceptual information about how CareKeeper works
- **Reference**: Feature reference and troubleshooting

**Local Preview**:
```bash
# Install dependencies
pip3 install -r requirements.txt

# Serve locally with live reload
./scripts/serve-docs.sh

# Visit http://localhost:8000
```

**Build for Production**:
```bash
# Build static site
./scripts/build-docs.sh

# Output in site/ directory
```

The results are deployed to Cloudflare Pages

**In-App Documentation**:
- Access help directly in the app via Menu > Help
- WebView integration displays full documentation site
- iOS-only feature (available on iPhone and iPad)

**Deployment**:
See [ADR 006: Cloudflare Pages Documentation Hosting](technical/adr/006-cloudflare-pages-documentation-hosting.md) for deployment decision rationale and detailed instructions.

**Screenshots**:
Use the screenshot capture helper to add images to documentation:
```bash
./scripts/capture-screenshots.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Security & Privacy

- **Local Encryption**: Device storage encrypted when locked (File Protection Complete)
- **CloudKit Encryption**: Automatic encryption in transit (TLS) and at rest on Apple servers
- **Collaborative Security Model**: Infrastructure-level encryption balances security with sharing functionality
- **No Third-Party Analytics**: Privacy-first approach with no data sold or shared
- **iCloud Account Security**: Protected by user's Apple ID credentials and two-factor authentication

## License

[MIT License](LICENSE) - Feel free to use this project as a foundation for your own care tracking apps.

## Support

- 📧 [Create an issue](https://github.com/kareemf/carekeeper/issues) for bug reports
