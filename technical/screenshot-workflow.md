# Simulator Screenshot Workflow

This guide records the workflow for producing sanitized screenshots for the OSS release and future portfolio updates. It covers both iOS and watchOS captures using Apple simulators, seeded demo data, and consistent status-bar styling.

## Goals
- Capture screens that reflect the shipping feature set (caree list/detail, activity tracking, diagnostics, etc.).
- Use only fictional/sample data so screenshots can be shared publicly.
- Produce consistent framing (status bar, watch bezel, locale, time) for marketing pages.

## Prerequisites
1. Install the required CLI tools (already noted in README):
   ```bash
   brew install xcodegen swiftformat swiftlint git-secrets
   ```
2. Generate and open the Xcode project (`xcodegen generate`).
3. Ensure `CareKeeper/Shared/Config.plist` points at non-production CloudKit/App Group IDs or fake containers so demo data doesn’t sync to real accounts.
4. Optional: create a dedicated build configuration (e.g., `Screenshots`) that forces demo data seeding and disables analytics/log streaming; for now the Debug build is sufficient because Preview data auto-loads for new installs.

## iOS Simulator Workflow
1. Boot a clean simulator:
   ```bash
   xcrun simctl boot "iPhone 16 Pro"
   ```
2. Reset status bar for clean UI (time, carrier, full battery):
   ```bash
   xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiBars 3 --batteryState charged --batteryLevel 100
   ```
3. Install + launch the app (from the latest Debug build):
   ```bash
   ./scripts/build-install-launch.sh # or manual xcodebuild + simctl install
   ```
4. Navigate to each screen you plan to showcase. Use seeded demo data (Caree “Jamie”, etc.) or manually add sanitized entries.
5. Capture PNGs via CLI (saves in `$PWD`):
   ```bash
   mkdir -p screenshots/ios
   xcrun simctl io booted screenshot screenshots/ios/caree-list.png
   xcrun simctl io booted screenshot screenshots/ios/activity-detail.png
   # repeat per screen
   ```
6. When finished, clear the status bar override:
   ```bash
   xcrun simctl status_bar booted clear
   ```

## watchOS Simulator Workflow
1. Boot the paired watch simulator (matching the phone used above):
   ```bash
   xcrun simctl boot "Apple Watch Ultra 2 (49mm)"
   ```
2. If you need a fresh environment, erase the watch simulator via Xcode or:
   ```bash
   xcrun simctl erase "Apple Watch Ultra 2 (49mm)"
   ```
3. Install + launch the watch app (Xcode run target or `xcrun simctl install booted` with the watch app bundle inside `CareKeeper Watch App.app`).
4. For consistent chrome, hide complications and set the status overlay (watchOS doesn’t expose the same API as iOS; rely on the simulator’s “Toggle Status Bar” option to show the minimal UI).
5. Capture screenshots:
   ```bash
   mkdir -p screenshots/watch
   xcrun simctl io booted screenshot screenshots/watch/caree-list.png
   xcrun simctl io booted screenshot screenshots/watch/activity-list.png
   ```
   > Note: `simctl io` uses the currently booted device. If both phone and watch are booted, specify the watch’s UDID (`xcrun simctl list devices` to find it) and pass `--device <UDID>`.

## Post-processing
- Trim or frame images in Preview/Pixelmator as needed (Apple recommends leaving the simulator bezel for App Store assets; for portfolio docs you can drop them).
- Store raw PNGs under `docs/media/` or `screenshots/` (git-ignored if only for marketing). Export resized variants for README/docs if desired.
- When adding to README or docs, use relative paths (e.g., `![Caree List](docs/media/caree-list.png)`).

## Automation Ideas (Optional)
- Script the flow via `scripts/capture-screenshots.sh`:
  - Build app, boot simulators, apply status bar overrides, navigate via UI tests or deeplinks, run `simctl io screenshot` for each target view.
  - Could leverage UI tests with `XCUIScreen.main.screenshot()` for more deterministic layout.
- Use Fastlane’s `snapshot` for iOS and `frameit` for templated frames (watchOS support is limited, so manual simctl remains simplest).

For now, manual navigation + `simctl io screenshot` is enough to produce OSS-friendly figures. Document new shots and keep the sample data fictional to avoid privacy leaks.
