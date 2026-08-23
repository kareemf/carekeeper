# Spec: Swift 6 Actor Isolation & Sendability Warnings

## Purpose & User Problem

The Xcode Cloud build of `bc93246` compiled successfully but emitted four warnings, each
labelled *"this is an error in the Swift 6 language mode"*. The project builds in Swift
5.0 mode today, so these are latent: they become hard build failures the moment the
language mode is raised.

Fixing them now is cheap and removes a future migration blocker. None were introduced by
recent work — they are pre-existing.

### Warning group 1 — `CaregiverDisplayNameService.swift` (3 warnings)

`recordType`, `recordName`, and `valueField` are `static let` constants on a `@MainActor`
class, read from inside the `Task.detached` block in `performCloudKitSync()`:

- `CaregiverDisplayNameService.swift:132` — `recordName`
- `CaregiverDisplayNameService.swift:142` — `recordType`
- `CaregiverDisplayNameService.swift:147` — `valueField`

(Line numbers current as of the merge of `caregiver-display-name-test-hygiene.md`,
which shifted them by +4. Warnings confirmed still present in that build.)

The detached task is non-isolated, so touching main-actor-isolated statics from it is the
violation. All three are immutable `String` constants and therefore inherently `Sendable`
— the isolation buys nothing.

### Warning group 2 — `CloudKitUserIdentityService.swift` (1 warning)

`CloudKitUserIdentityService.swift:8` declares `extension CKContainer:
CloudKitUserRecordIDFetching {}`. The protocol requirement at line 5 is:

```swift
func fetchUserRecordID(completionHandler: @escaping (CKRecord.ID?, Error?) -> Void)
```

but `CKContainer`'s actual method marks the closure `@escaping @Sendable`. The sendability
of the function types does not match, so the conformance is only valid in Swift 5 mode.

## Success Criteria

1. All four warnings are gone from a clean build.
2. No new warnings introduced.
3. Runtime behaviour is unchanged — these are type-system annotations only.
4. `CareKeeperTests` still passes.

## Scope & Constraints

- Touch only `CaregiverDisplayNameService.swift` and `CloudKitUserIdentityService.swift`.
- Do **not** raise `SWIFT_VERSION` or set `SWIFT_STRICT_CONCURRENCY` — adopting Swift 6
  mode is a much larger piece of work and is out of scope here.
- Fix the warnings at their cause; do not silence them with `@unchecked Sendable`,
  `nonisolated(unsafe)`, or by suppressing the diagnostic.
- `caregiver-display-name-test-hygiene.md` has now landed, so there is no longer a
  conflict risk from that work.

## Technical Considerations

**Group 1**: mark the three constants `nonisolated static let`. They are immutable
`String`s, so this is safe and precise — it states the truth that these constants were
never main-actor state. Moving them out of the class into a private enum would also work
but changes call sites unnecessarily.

**Group 2**: add `@Sendable` to the protocol requirement so it matches `CKContainer`:

```swift
func fetchUserRecordID(completionHandler: @escaping @Sendable (CKRecord.ID?, Error?) -> Void)
```

Check whether the test double conforming to this protocol (used by
`currentUserRecordName(fetcher:)`) needs the same annotation.

**Verification**: DONE. Both fixes were applied in a scratch worktree and built against
iPhone 16 Pro / iOS 18.6:

- `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, 119 tests, 0 failures
- 0 Swift compile errors
- All four targeted warnings eliminated (confirmed by before/after diff of the logs)
- `nonisolated static let` is accepted on the `@MainActor` class in Swift 5.0 mode
- `FakeUserRecordFetcher` (`CloudKitUserIdentityServiceTests.swift:20`) needs NO change:
  its plain `@escaping` parameter is broader than the now-`@Sendable` requirement, and
  function parameters are contravariant, so it still satisfies the protocol

Reviewer note (claude, after the build): both changes are semantically correct rather
than incidentally compiling. Static `let` init is `swift_once`-guarded, so the thread
safety already held at runtime and the isolation was only ever a compile-time rule. The
`@Sendable` addition corrects a protocol that was under-declaring `CKContainer`'s actual
signature, so it tightens the contract rather than hiding a race. Caveat: validated in
Swift 5 mode only; full Swift 6 adoption may want a matching `@Sendable` on the test fake.

**Note on a fresh worktree/clone**: `scripts/ensure-config.sh` aborts unless
`CareKeeper/Shared/Config.plist` (gitignored) exists or `CLOUDKIT_CONTAINER_ID` is set,
so the build fails at `PhaseScriptExecution Ensure Config.plist` before compiling. Copy
the plist in first. Unrelated to this spec, but it blocks verification.

## Tasks

- [x] Mark CaregiverDisplayNameService record constants nonisolated
- [x] Add @Sendable to CloudKitUserRecordIDFetching protocol requirement
- [x] Clean build and confirm all four warnings are resolved with no new ones
  - result: BUILD/TEST SUCCEEDED, 119 tests 0 failures, 4/4 warnings gone,
    0 new warnings; one unrelated warning remains (see Out of Scope)

## Out of Scope

- Migrating the project to the Swift 6 language mode.
- Enabling `SWIFT_STRICT_CONCURRENCY` at any level.
- Any other Swift 6 warnings not in the four listed above (a full audit may surface more
  once strict concurrency is actually enabled). One is already known and remains after
  this work: `CloudKitSharedRecordsServiceConversionTests.swift:42` — `isMainThread` is
  unavailable from asynchronous contexts. Xcode Cloud did not report it because it builds
  the app targets, not the test target.
- Adding `@Sendable` to `FakeUserRecordFetcher` — unnecessary in Swift 5 mode, may be
  wanted for full Swift 6 adoption.
