# Share Participant Performance Improvements (Codex)

**Status**: Proposed  
**Created**: 2025-11-22  
**Author**: Codex, Claude Code 
**Audience**: iOS, CloudKit, Performance

---

**Scope update**: Focus on four immediate items: (1) batched cache writes via `replaceCaree`, (2) change-token–based incremental sync, (3) refresh throttling/concurrency guards, (4) UI optimizations (pagination + lightweight counts). Defer history windowing until requested.

## Problem Summary
- Share participants on the same build see the app become sluggish, freeze, or crash after a few minutes of use; Caree owners on the same device do not.
- Shared data ingestion eagerly downloads every record (carees, activity types, activities) on each refresh and upserts them into the local cache record-by-record (`CloudKitSharedRecordsService.fetchSharedCarees`, `applySharedResultsToCache`, `LocalCacheService.cacheActivity/cacheActivityType`), resulting in hundreds of individual SwiftData saves for a caree with ~300 activities. Owners use a single `replaceCaree` call that batches saves, so they avoid this churn.
- The UI renders entire activity arrays for shared carees (Caree list counts via `caree.activities?.count`, ActivityList showing the full list, CareeDetail sorting all `recentActivities`). With 300+ activities and repeated refreshes, this drives CPU/memory pressure and long main-thread work.
- Each CloudKit push, manual refresh, or view appearance triggers a full shared re-query (`fetchSharedCarees`) rather than an incremental delta, redoing the heavy work even when only a few records changed.
- A collaborator proposed similar mitigations (time-windowed activity queries, pagination, incremental cache updates, lightweight counts, change-token deltas). The plan below integrates the pieces we agree with, notes risks where we differ (e.g., default window length, CloudKit count queries), and calls out items needing confirmation. Given current representative payload size (~152 KB for ~3 carees with ~350 activities), we’re deferring selective desiredKeys trimming unless payloads grow materially. History windowing is explicitly deferred for now.

## Likely Causes (ranked)
- **Per-record cache writes for shared data**: `applySharedResultsToCache` loops through every activity/activity type and calls `cacheActivity`/`cacheActivityType`, each performing its own `modelContext.save()`. This is O(N) disk writes per refresh for participants, versus a single batched save for owners. Symptom aligns with participant-only slowdown.
- **Full-graph reloads on every shared refresh**: Shared fetches pull all records every time and rebuild arrays, with no pagination or change-token constrained queries. As activity counts grow, total work grows linearly and repeats frequently.
- **UI forces full materialization**: Counts and lists read `caree.activities` directly, so SwiftData must load and sort the whole collection even when only a handful of rows are shown (CareeList rows, CareeDetail recent list, ActivityList). With large collections, this adds main-thread cost and memory churn.
- **Refresh storm risk**: Shared notifications (`handleCloudKitNotification`), `.refreshable` pulls, and cache refreshes all trigger full `fetchSharedCarees`, causing repeated heavy work within short windows on participant devices.
- **Optional activity windowing**: Constraining shared fetches to a recent window (default to 14 days) can cap payloads, but risks hiding history unless paired with an explicit “load older” path and/or a user setting. Needs product guidance before enforcing beyond the default.

## Plan

### Phase 0 — Confirm & Instrument
- Capture participant device diagnostics: sysdiagnose/crash logs, memory warnings, and timeline of when freezes occur relative to refreshes.
- Add lightweight logging/metrics around shared refreshes (duration, record counts, save counts, memory via `MemoryMonitor`) to reproduce locally with a seeded 300+ activity shared caree.

### Phase 1 — Shared Ingestion Efficiency (highest impact)
- Replace per-record cache writes with batched replacements for shared carees (mirror owner path): in `applySharedResultsToCache`, call `replaceCaree` once per caree with full child arrays, avoiding hundreds of `modelContext.save()` calls.
- Where change sets are small, consider a differential update path to avoid delete/recreate churn: detect adds/updates/deletes relative to the cached caree and apply only those mutations in a single save (still avoid per-record saves). Guardrails: use the delta path when total mutations (adds+updates+deletes) are below ~50 or under ~10% of the cached activity count; otherwise fall back to full `replaceCaree` so we don’t reintroduce the per-record root problem.
- Skip selective field trimming for now: current representative payload (~152 KB) doesn’t justify desiredKeys complexity. Focus on batching and pagination first; revisit trimming if payloads grow materially (large notes/attachments).

### Phase 2 — Incremental Shared Sync
- Add change-token driven deltas for shared zones: reuse `SharedZoneChangeTokenStore` with `CKFetchRecordZoneChangesOperation` to pull only new/updated records after initial backfill; fall back to full resync on token expiry. Sequence: ship batched shared writes first for immediate relief, then enable deltas. Revisit delta thresholds or grace fallback if token churn or server errors make deltas unstable.

### Phase 3 — Refresh Concurrency/Throttling
- Throttle shared refresh triggers (debounce repeated pushes/refreshables) and surface spinner/state to avoid overlapping full fetches. Enforce a single in-flight shared fetch; queue or drop redundant triggers. Revisit concurrency model if we need partial refreshes per caree.

### Phase 4 — UI/Data Access Shaping
- Introduce paginated activity loading: `ActivityListView` should fetch in pages (e.g., 50 at a time ordered by `dateTime`) with an explicit “Load more” control; keep only the visible window in memory. Chosen over infinite scroll for clearer user intent and easier memory bounds; revisit infinite scroll if usability testing shows repeated “Load more” taps are a burden for long histories.
- Use lightweight counts instead of materializing arrays: prefer cached count fields maintained during ingestion/sync (e.g., `activityCount`, `activityTypeCount`, windowed counts when windowing is on), with `fetchCount` as a spot-check or fallback when cache consistency is uncertain (e.g., after a failed write or migration). This avoids repeated fetch/sort work on every row render while keeping a recovery path; revisit heavier fetchCounts if we observe cache drift we cannot cheaply reconcile during ingestion.
- Limit recent activity reads: cap CareeDetail recent list to a small slice via a targeted fetch (e.g., top 20 by date) instead of sorting the entire collection on the main thread.
- Store/refresh derived fields on carees (e.g., `lastActivityAt`, `activityCount`) during ingestion to avoid repeated sorting/scanning at view time.
- Prefer deriving counts during ingestion/cache updates rather than issuing extra CloudKit count-only queries per caree/zone (count queries are still expensive across shared zones); only reach for CloudKit counts when we need to repair or validate cache-derived counts after suspected drift. If windowing is on, maintain two counters in cache: visibleCount (within window) and totalCount updated via change deltas without pulling all historical records; fall back to a periodic full count only if deltas prove unreliable or after recovery from token loss.
- Use SwiftData-targeted queries (e.g., sorted/limited @Query or fetch descriptors) for recent slices instead of computed properties that sort the entire array on every access.

### Phase 4 — Optional Future Improvements
- Add optional activity windowing for shared queries (deferred): do not implement now. If product requests, consider a user-visible “load older” path and a default window (prior proposal: 14 days; collaborator: 30 days). Revisit when payload size or UX demands it.
- Revisit selective desiredKeys trimming if payloads grow materially (e.g., very large notes/attachments); pair with background hydration to preserve offline detail access.
  - For selective field fetching: keep offline support by hydrating full fields into cache in the background after the lightweight fetch (or immediately when full payloads are cheap). The list can use the trimmed record shape, but a follow-up fetch should fill in notes/quantity/location so detail views remain available offline without the user having opened each activity.


### Phase 5 — Verification
- Build a test fixture with a shared caree containing 300–500 activities and run on a participant account; validate scroll/jank, memory, and crash-free operation before/after changes.
- Add regression checks: timers for shared fetch duration, total cache save count per refresh, and UI responsiveness (FPS/perf in Instruments) as acceptance criteria.

## What I Still Need
- Participant crash logs or sysdiagnose showing memory pressure or watchdog terminations.
- Confirmation of dataset scale on the affected participant (carees shared, activity counts per caree, presence of images).
- Whether freezes also occur on the caree owner when they join someone else’s share (to validate shared-path hypothesis).
- History windowing: deferred. We’ll re-ask for UX guidance if/when we propose enabling it.

## Spec Detail Level (implementation references to keep)
- Keep concrete entry points and key classes that future engineers will need to touch (e.g., `CloudKitSharedRecordsService.fetchSharedCarees`, `applySharedResultsToCache`, `LocalCacheService.replaceCaree`, `ActivityListView` query points) and describe the intended control flow at those seams.
- Include representative fetch descriptors/@Query shapes (limits, sort key `dateTime`, predicates for windowing/pagination) so pagination and limited fetches are implemented consistently.
- Note derived fields expected on models (e.g., `activityCount`, `activityTypeCount`, `lastActivityAt`, windowed counts) and where they are set during ingestion to avoid regressions.
- Call out performance-oriented invariants and guardrails (e.g., “shared ingestion must batch to a single save per caree”, “UI lists must not materialize full activity arrays”, pagination page size defaults, debounce requirements for refreshes).
- Exclude low-level line numbers or transient scaffolding unless they encode an invariant; prefer durable identifiers (function names, model properties) and rationale so the spec remains valid after refactors.

## What I Can Do Now (given current info)
- Implement the shared ingestion refactor (batched cache replace), enable change-token deltas, add refresh throttling/concurrency guards, and ship UI pagination/count fixes above.
- Add instrumentation to reproduce locally with seeded data to ensure participant paths stay performant as activity counts grow.

## Branching/commits
- Work on branch `feature/share-participant-perf`; commit after each milestone/phase (batched writes, change tokens, refresh throttling, UI pagination/counts) to keep reviews digestible.
