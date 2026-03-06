# Rename CareKeeper → QuickCareKeeper

## Context
The name "CareKeeper" is taken on the App Store ([CareKeeper AI](https://apps.apple.com/us/app/carekeeper-ai-patient-notes/id6746745634)). Renaming to **QuickCareKeeper** to avoid conflicts. The CloudKit container `iCloud.com.kareemf.CareKeeper2` must NOT be changed (destructive operation).

**This is a NEW App Store listing.** The bundle ID change means existing installs cannot be updated in-place. Users must install the new app. CloudKit data persists because the container ID is unchanged.

## Approach
Systematic rename in dependency order: source files first, then config, then directories. XcodeGen regenerates the `.xcodeproj` so we focus on `project.yml` and let XcodeGen handle the rest.

## Critical Constraint
`iCloud.com.kareemf.CareKeeper2` must **NEVER** be changed. All replacements are targeted (not blind find-replace of "CareKeeper"). Post-step verification after each edit.

### Replacement Strategy
- `com.kareemf.CareKeeper` → `com.kareemf.QuickCareKeeper` (bundle IDs)
- `group.com.kareemf.CareKeeper` → `group.com.kareemf.QuickCareKeeper` (app groups)
- `CareKeeperApp` → `QuickCareKeeperApp` (Swift symbols)
- `CareKeeper Watch App` → `QuickCareKeeper Watch App` (target/directory names)
- `CareKeeper Widget` → `QuickCareKeeper Widget`
- **NEVER** match `iCloud.com.kareemf.CareKeeper2` — this string is excluded from all replacements
- After each file edit: verify `iCloud.com.kareemf.CareKeeper2` still present where expected

---

## Step 0: Apple Developer Portal & App Store Connect (Manual — User Action)

- Register new App IDs: `com.kareemf.QuickCareKeeper`, `.watchkitapp`, `.widget`
- Register new App Group: `group.com.kareemf.QuickCareKeeper`
- Add CloudKit container `iCloud.com.kareemf.CareKeeper2` to the **new** App IDs
- Generate/update provisioning profiles for all targets
- Create new App Store Connect record (new SKU, bundle ID mapping)
- TestFlight pipeline configuration

> **Note:** This step must complete before builds succeed on real devices.

## Step 1: Update `project.yml`

**File:** `project.yml`

| Old | New |
|-----|-----|
| `name: CareKeeper` | `name: QuickCareKeeper` |
| `com.kareemf.CareKeeper` | `com.kareemf.QuickCareKeeper` (all variants: `.watchkitapp`, `.widget`, `Tests`, `UITests`) |
| `group.com.kareemf.CareKeeper` | `group.com.kareemf.QuickCareKeeper` |
| Display names: `CareKeeper` | `QuickCareKeeper` |
| `WKCompanionAppBundleIdentifier` | `com.kareemf.QuickCareKeeper` |
| Target names, scheme refs, source paths | Update to match new directory names |

**Verify:** `iCloud.com.kareemf.CareKeeper2` unchanged in project.yml.

## Step 2a: Update entitlements file CONTENTS (not filenames yet)

**Files:**
- `CareKeeper/CareKeeper.entitlements`
- `CareKeeper Watch App/CareKeeper Watch App.entitlements`
- `CareKeeper Widget/CareKeeper Widget.entitlements`

Update app group IDs inside. **Keep** `iCloud.com.kareemf.CareKeeper2` unchanged. Files stay at current paths until Step 7b.

## Step 3: Update Config plist files

**Files:**
- `CareKeeper/Shared/Config.plist` — update app group ID
- `CareKeeper/Shared/Config.default.plist` — update app group ID

**Keep** CloudKit container ID unchanged in both.

## Step 4: Update Info.plist files

**Files:**
- `CareKeeper/Info.plist` — CFBundleDisplayName
- `CareKeeper-Watch-App-Info.plist` — display name, WKCompanionAppBundleIdentifier
- `CareKeeper-Widget-Info.plist` — display name

## Step 5: Update Swift source files

**Struct/class renames:**
- `CareKeeperApp` → `QuickCareKeeperApp` (`CareKeeper/iOS/App/CareKeeperApp.swift`)
- `CareKeeperWatchApp` → `QuickCareKeeperWatchApp` (`CareKeeper Watch App/App/CareKeeperWatchApp.swift`)
- `CareKeeperWidget` → `QuickCareKeeperWidget` (`CareKeeper Widget/CareKeeperWidget.swift`)
- `CareKeeperWidgetBundle` → `QuickCareKeeperWidgetBundle` (`CareKeeper Widget/CareKeeperWidgetBundle.swift`)

**Logger subsystem:**
- `CloudKitZoneDiscoveryService.swift` — `"com.kareemf.CareKeeper"` → `"com.kareemf.QuickCareKeeper"`

**String references in CloudKitConfig.swift** — update example/placeholder text

## Step 6: Rename Swift source filenames

- `CareKeeperApp.swift` → `QuickCareKeeperApp.swift`
- `CareKeeperWatchApp.swift` → `QuickCareKeeperWatchApp.swift`
- `CareKeeperWidget.swift` → `QuickCareKeeperWidget.swift`
- `CareKeeperWidgetBundle.swift` → `QuickCareKeeperWidgetBundle.swift`

## Step 7a: Rename directories

Order matters — rename leaf directories first, then parents:
1. `CareKeeperTests/` → `QuickCareKeeperTests/`
2. `CareKeeperUITests/` → `QuickCareKeeperUITests/`
3. `CareKeeper Widget/` → `QuickCareKeeper Widget/`
4. `CareKeeper Watch App/` → `QuickCareKeeper Watch App/`
5. `CareKeeper/` → `QuickCareKeeper/` (main iOS source)

## Step 7b: Rename entitlements FILENAMES (post-directory rename)

- `QuickCareKeeper/CareKeeper.entitlements` → `QuickCareKeeper/QuickCareKeeper.entitlements`
- `QuickCareKeeper Watch App/CareKeeper Watch App.entitlements` → `QuickCareKeeper Watch App/QuickCareKeeper Watch App.entitlements`
- `QuickCareKeeper Widget/CareKeeper Widget.entitlements` → `QuickCareKeeper Widget/QuickCareKeeper Widget.entitlements`

## Step 8a: Update CI and linting config

- `.github/workflows/ci.yml` — scheme name, test target
- `.swiftlint.yml` — excluded paths

## Step 8b: Update scripts

- `scripts/build-install-launch.sh` — scheme names, bundle IDs, DerivedData paths, xcodeproj name
- `scripts/sync-ios-to-watch-sim.sh` — `APP_GROUP_ID`, bundle IDs
- `scripts/ensure-config.sh` — Config.plist path
- `scripts/build-docs.sh`, `scripts/serve-docs.sh`, `scripts/capture-screenshots.sh` — display text

## Step 9: Update documentation

**Files (targeted find-replace `CareKeeper` → `QuickCareKeeper`, skipping CloudKit container ID):**
- `README.md`
- `CLAUDE.md`
- `mkdocs.yml`
- All files in `docs/` (~14 files)
- All files in `technical/` (~16 files)

**Preserve** any reference to the CloudKit container ID.

## Step 10: Regenerate Xcode project

```bash
xcodegen generate
```

This regenerates `QuickCareKeeper.xcodeproj` from the updated `project.yml`. Old `.xcodeproj` and scheme files are replaced automatically.

## Step 11 (DEFERRED/OPTIONAL): Rename git repo directory

```bash
cd .. && mv CareKeeper QuickCareKeeper && cd QuickCareKeeper
```

Only if user explicitly requests. Decoupled from app rename. User will rename the GitHub remote repo separately if desired.

## Step 12: Update auto-memory

Update the Claude memory directory path reference (if any hardcoded paths exist).

---

## Exclusions (DO NOT CHANGE)
- `iCloud.com.kareemf.CareKeeper2` — CloudKit container identifier (appears in entitlements and Config plists)

## Verification Checklist
1. `xcodegen generate` succeeds without errors
2. iOS build: `xcodebuild -scheme QuickCareKeeper -destination 'platform=iOS Simulator,name=iPhone 16' build`
3. watchOS build: `xcodebuild -scheme "QuickCareKeeper Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build`
4. Widget build: `xcodebuild -scheme "QuickCareKeeper Widget" -destination 'platform=iOS Simulator,name=iPhone 16' build`
5. `grep -r "CareKeeper" --include="*.swift" --include="*.yml" --include="*.plist" --include="*.entitlements" --include="*.sh" . | grep -v "iCloud.com.kareemf.CareKeeper2" | grep -v DerivedData` returns no results
6. `grep -l "iCloud.com.kareemf.CareKeeper2"` confirms presence in all 3 entitlements files
7. `WKCompanionAppBundleIdentifier` = `com.kareemf.QuickCareKeeper` confirmed in watch plist/project.yml

## Review History
- **v1**: Initial plan
- **v2**: Added Step 0 (Apple Developer Portal), Step 8b (scripts), targeted replacement strategy, split entitlements sequencing, deferred repo rename, expanded verification
- **v3 (approved)**: Added App Store Connect to Step 0, widget build to verification, clarified Step 2a/7b split
