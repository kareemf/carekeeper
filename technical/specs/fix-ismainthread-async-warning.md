# Spec: Fix `Thread.isMainThread` Async-Context Warning

## Purpose & User Problem

`CareKeeperTests/CloudKitSharedRecordsServiceConversionTests.swift` emits the last
remaining Swift 6 warning in the project:

```
CloudKitSharedRecordsServiceConversionTests.swift:42:28: warning: class property
'isMainThread' is unavailable from asynchronous contexts; Work intended for the main
actor should be marked with @MainActor; this is an error in the Swift 6 language mode
```

It is invisible in Xcode Cloud, which builds the app targets but not the test target, so
it will only surface as a hard failure whenever the language mode is raised.

A **second, unrelated warning** in the same file was found while investigating:

```
CloudKitSharedRecordsServiceConversionTests.swift:11:70: warning: no 'async' operations
occur within 'await' expression
```

### Why the isMainThread check is the wrong tool

`testConvertRecordsSyncRunsOffMainThread` (lines 32-44) wraps the call in
`Task.detached` and asserts `!Thread.isMainThread`. The closure passed to `Task.detached`
is an async context, which is what triggers the diagnostic.

Swift marks `Thread.isMainThread` unavailable there because a task may suspend and resume
on a different thread, so the answer is not a stable property of the work — it is a
snapshot of one instant.

More importantly, the property the test wants is **already guaranteed at compile time**:

- `CloudKitSharedRecordsService.swift:669` — `nonisolated static func convertRecordsSync`
- `CloudKitSharedRecordsService.swift:656` — `nonisolated func convertRecordsOffMain`

Both are `nonisolated` and synchronous on an otherwise `@MainActor` class. Being callable
without main-actor isolation is enforced by the type system, not by runtime luck.

### Why line 11 warns

`convertRecordsOffMain` is `nonisolated` and **synchronous** (`throws`, not `async
throws`). The test calls it as `try await service.convertRecordsOffMain(...)`, so the
`await` is redundant — there is no suspension point. Calling a `nonisolated` synchronous
function from a `@MainActor` context needs no `await`.

## Success Criteria

1. Both warnings are gone from a clean build of the test target.
2. `CloudKitSharedRecordsServiceConversionTests` still passes.
3. Full `CareKeeperTests` target still passes (119 tests, 0 failures).
4. The intent of `testConvertRecordsSyncRunsOffMainThread` — that conversion is usable off
   the main actor — is still covered, not silently dropped.
5. Zero Swift 6 warnings remain project-wide.

## Scope & Constraints

- Touch only `CareKeeperTests/CloudKitSharedRecordsServiceConversionTests.swift`.
- Do **not** change `CloudKitSharedRecordsService.swift` — the production code is correct;
  only the test's assertion mechanism is at fault.
- Do not silence via `@available`, `#warning` suppression, or by deleting the test.
- Do not raise `SWIFT_VERSION` or enable `SWIFT_STRICT_CONCURRENCY`.

## Technical Considerations

### Warning 1 — two viable approaches

**Option A (recommended): sample the thread from a synchronous helper.**

```swift
private nonisolated static func isOffMainThread() -> Bool { !Thread.isMainThread }
```

Call it from inside the detached closure. `Thread.isMainThread` is perfectly legal in a
synchronous context, where "which thread am I on right now" is a well-defined question.
This is not a dodge of the diagnostic — it relocates the check to the only context where
it has meaning, and preserves the test's existing runtime assertion exactly.

*Trade-off*: keeps a runtime check that is inherently a snapshot. It passes today and is
very unlikely to flake, since a `.utility` detached task will not be scheduled on the main
thread, but it asserts a scheduling detail rather than a contract.

**Option B: drop the thread assertion, rely on the compile-time guarantee.**

Keep the `Task.detached` call, assert on the returned conversion results, and delete the
`Thread.isMainThread` check. If someone later marks `convertRecordsSync` as `@MainActor`,
the call site must gain an `await` to compile — a visible, reviewable change.

*Trade-off*: the regression signal becomes "a diff you must notice in review" rather than
"a red test". Weaker as a guard, but removes an unreliable runtime assertion entirely.

**Recommendation**: Option A. It is the smaller change, keeps a real runtime assertion,
and is semantically honest. Option B is worth taking only if we decide the runtime check
was never earning its keep.

**DECIDED: Option A** (approved 2026-08-23). Implementation and review model: claude
(codex was out of quota).

### Warning 2

Remove the redundant `await` on line 11. Leave the test method `async throws` — XCTest
supports async test methods, and `Task.detached(...).value` in the sibling test still
requires it. Verify the `async` keyword is still warranted on *this* method after the
change; if nothing else in it suspends, it may be dropped, but that is optional and not
required to clear the warning.

### Verification

Requires the iOS 26.5 / watchOS 26.5 simulator runtimes (now installed). A fresh worktree
also needs `CareKeeper/Shared/Config.plist` copied in, or `ensure-config.sh` aborts before
compiling — see `swift6-actor-isolation-warnings.md`.

Confirm with a before/after grep of the build log for
`this is an error in the Swift 6 language mode`; the expected count after this work is
**zero** project-wide.

## Tasks

- [x] Replace the async-context `Thread.isMainThread` check with a synchronous helper
  - branch: `impl/ismainthread-sync-helper`
  - status: `complete`
- [x] Remove the redundant `await` on the `convertRecordsOffMain` call
  - branch: `impl/remove-redundant-await`
  - status: `complete`
- [x] Clean build and confirm zero Swift 6 warnings project-wide, 119 tests still passing
  - result: BUILD/TEST SUCCEEDED, 119 tests 0 failures, 0 Swift errors,
    0 Swift 6 warnings project-wide, no warnings left in the file

## Follow-up Findings (from review, not actioned)

Raised by the reviewer during this work. None blocked the change; all are outside the
scope approved for this spec.

1. **The off-main test discards its result.** `_ = try convertRecordsSync(...)` — nothing
   asserts the conversion is *correct* while running off-main. The sibling test checks
   correctness but calls the instance wrapper from the `@MainActor` test method, so it
   runs on main. Nothing in the file asserts correct relationships while genuinely
   off-main.
2. **The thread guarantee is positional, not structural.** It holds only because no
   `await` sits between the work and the sample. Insert one later and the sample silently
   decouples from where the work ran — the test keeps passing while measuring nothing, a
   quiet false pass. A helper returning `(result, ranOffMain)` from one synchronous frame
   would make it structural and fix finding 1 at the same time.
3. **The new doc comment explains the diagnostic, not the invariant.** What makes the call
   site sound is the absence of a suspension between work and sample — that is what a
   future editor must not break, so that is what the comment should say.
4. **`convertRecordsOffMain` is a misleading name** (`CloudKitSharedRecordsService.swift:656`).
   Its own doc comment concedes it "Runs inline". The production call site at line 608 in
   `fetchSharedCarees` invokes it on the main actor — the place to look if large shared
   record sets ever cause UI hitches. Production concern, unrelated to the warnings.
5. **`async` on `testConvertRecordsOffMainBuildsRelationships` is now dead** — no
   suspension points remain. Harmless; Swift does not warn.

## Out of Scope

- Migrating the project to Swift 6 language mode.
- Any change to `CloudKitSharedRecordsService.swift`.
- Broadening test coverage of the conversion logic itself.
