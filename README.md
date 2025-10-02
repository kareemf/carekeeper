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

1. Select your target device or simulator
2. Choose either "CareKeeper" (v1) or "CareKeeperV2" (v2) scheme
3. Build and run the project (⌘+R)

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

### Running Tests

```bash
# Unit tests
⌘+U in Xcode

# UI tests (when implemented)
⌘+U with UI test target selected
```

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