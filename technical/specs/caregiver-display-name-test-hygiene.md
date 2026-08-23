# Spec: CaregiverDisplayNameService Test Hygiene

## Purpose & User Problem

`CareKeeperTests/CaregiverDisplayNameServiceTests.swift` was added in PR #4 but was
never a member of the `CareKeeperTests` target — `project.pbxproj` was not regenerated.
The file was wired into the target in commit `bc93246`, so these 14 tests are about to
execute for the first time.

Reading the file against `CaregiverDisplayNameService` surfaced two defects that will
take effect the moment the tests actually run:

1. **The tests perform live CloudKit network I/O.**
   `init(testing:)` leaves `isSuppressingSync == false`, so every assignment to
   `service.displayName` fires `didSet` → `syncToCloudKit()`, which schedules a task that
   sleeps 2s and then issues a `Task.detached` `CKContainer` write against the real
   container (`CaregiverDisplayNameService.swift:33-39, 73-81, 132-159`). Six tests assign
   `displayName`. Writes are fire-and-forget with errors swallowed, so tests still pass —
   but a unit test suite should not touch the network. In Xcode Cloud, with no iCloud
   account, every one of these fails and logs warnings.

2. **`tearDown` cleanup targets the wrong UserDefaults suite.**
   Each test builds a unique suite (`...CaregiverDisplayName.<UUID>`), but the private
   `UserDefaults.suiteName` extension returns a **fixed** string
   (`CaregiverDisplayNameServiceTests.swift:104-110`), so
   `removePersistentDomain(forName:)` clears a domain that was never written. The real
   suites are never cleaned up and accumulate in the test host's defaults. Tests still
   pass — each gets a fresh UUID suite, so there is no cross-contamination — but it is a
   leak, and the extension's own comment signals the author knew it was off.

## Success Criteria

1. The 14 tests in `CaregiverDisplayNameServiceTests` compile and pass.
2. Running the suite issues **zero** CloudKit requests.
3. Each test's UserDefaults suite is actually removed in `tearDown`.
4. Production behaviour of `CaregiverDisplayNameService` is unchanged — the real
   `shared` instance must still sync to CloudKit on `displayName` changes, both
   debounced and immediate.
5. No other test target behaviour regresses.

## Scope & Constraints

- Touch only `CaregiverDisplayNameService.swift` and
  `CaregiverDisplayNameServiceTests.swift`.
- Preserve the existing public API used by callers (`SharingView`,
  `DisplayNamePromptModifier`, `CareKeeperApp`, watchOS `WatchDataProvider`).
- Match existing codebase patterns; the project is Swift 5.0 language mode with no
  strict concurrency setting.
- No new dependencies, no new test framework — stay on XCTest.

## Technical Considerations

**Issue 1** — preferred approach: give the service an explicit flag controlling whether
CloudKit sync is permitted, set to `false` by the testing initializer and `true` by the
private production initializer. Guard both `syncToCloudKit()` and
`syncToCloudKitImmediately()` on it. This keeps `shared` behaviour byte-identical while
making the test path inert, and avoids introducing a protocol seam for a single flag.

An alternative — injecting a sync closure or CloudKit protocol — is more testable in
principle but is a larger refactor than the defect warrants; note it as future work
rather than doing it here.

**Issue 2** — store the generated suite name in a test property (e.g. `suiteName`) and
use it in `tearDown`, then delete the misleading private `UserDefaults` extension
entirely. Nothing else references it.

**Verification constraint**: the full `clean build test` currently cannot run on this
machine — Xcode 26.6 ships the 26.5 SDKs while the installed simulator runtimes stop at
26.4, so asset-catalog compilation fails for the Watch App. The iOS 26.5 and watchOS 26.5
runtimes are downloading. Tests must be run to confirm, and the work is not complete
until they have been.

## Tasks

- [x] Suppress CloudKit sync in the testing initializer of CaregiverDisplayNameService
  - branch: `impl/suppress-cloudkit-sync-in-tests`
  - status: `complete`
- [x] Fix UserDefaults suite cleanup in CaregiverDisplayNameServiceTests tearDown
  - branch: `impl/fix-userdefaults-suite-cleanup`
  - status: `complete`
- [x] Run the CareKeeperTests suite and confirm all CaregiverDisplayNameService tests pass
  - result: 14/14 passed; full target 119 tests, 0 failures; zero CloudKit sync
    warnings logged; no new compiler warnings introduced

## Out of Scope

- Refactoring `CaregiverDisplayNameService` behind a CloudKit protocol seam.
- Adding test coverage for the CloudKit sync paths themselves
  (`fetchFromCloudKit`, `performCloudKitSync`), which remain untested.
- Re-enabling the disabled GitHub Actions CI workflow.
- The `MARKETING_VERSION` / TestFlight release flow.
