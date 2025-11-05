# Watch Log Streaming & Diagnostics Enhancements

> **Status (2025-11-04):** This initiative is paused. File-based logging and real-time streaming were removed from the app to eliminate their performance overhead on watchOS. The plan remains here for future reference if we revisit the feature.

## Context
- The watch caches CloudKit snapshots in the shared app-group. When the container is unavailable, both the cache and the existing file-based `FileLogger` fail silently, making it hard to diagnose issues.
- We want an optional log streaming channel to the paired iPhone and improved diagnostics so we can understand failures quickly.

## Goals
1. Keep cached data resilient while emitting warnings instead of crashing when the app-group container is missing.
2. Provide an optional log streaming pipeline—off by default—that can forward WARN/ERROR (and optionally INFO) entries from the watch to the phone for real-time debugging.
3. Enhance the diagnostics screen/export to surface streamed logs, container availability, and reasons the file logger might be inactive.

## Non-Goals
- No change to the existing CloudKit query pipeline.
- No integration with third-party log aggregation—everything remains local to the paired phone/watch.

## Design

### Shared Configuration
- Add `watchLogStreamingLevel` to the shared app-group defaults. Possible values:
  - `off` (default)
  - `warnError`
  - `info`
- Drive this from the iOS diagnostics screen (segmented control). Update the watch via shared defaults + `WCSession` message when it changes.
- Display the active level on the watch diagnostics page so support can confirm streaming state at a glance.

### Watch Streaming Service
- Introduce `WatchLogStreamService`:
  - Observes `watchLogStreamingLevel`.
  - Wraps FileLogger writes so that when streaming is enabled it forwards entries to the service.
  - Applies severity filtering and queue limits:
    - WARN/ERROR: keep ~200 recent entries.
    - INFO: keep ~50 entries and throttle if backlog grows (e.g., drop INFO when queue > threshold).
  - Uses `WCSession.sendMessage` when reachable; otherwise enqueues via `transferUserInfo`.
  - Each payload includes timestamp, level, message, optional metadata (e.g., cache availability).
  - When level flips to `off`, stops enqueueing and clears the buffer.
- Add a small indicator view/badge in the watch diagnostics UI (“Streaming: Warn+” / “Streaming: Info”).

### iPhone Receiver
- Implement `WatchLogStreamController` that conforms to `WCSessionDelegate` to receive streamed logs.
  - Appends entries to an in-memory buffer.
  - Writes entries to an app-group log file for persistence (e.g., append to `diagnostics/stream-log.txt`).
  - Posts a NotificationCenter update so `WatchDiagnosticsView` can refresh live entries.
- Update the diagnostics export flow to bundle the stream log alongside existing file logs.

### Diagnostics Enhancements
- `WatchDiagnosticsView.loadDiagnosticFiles`:
  - Log structured context when no files are found (`FileLogger.shared.isLoggingAvailable`, container path, errors).
  - Show the streaming selector (Off / Warn+ / Info) and live stream entries in a dedicated section.
  - Display queue length, last received timestamp, and any warnings (e.g., “watch reachable but stream empty”).

## Testing / Validation
- Unit tests:
  - `WatchCacheService` fallback guards and `checkAvailability`.
  - `WatchLogStreamService` buffer limits + severity filtering.
- Manual QA:
  1. Enable streaming (Warn+), trigger logs on the watch, verify the phone UI shows them immediately.
  2. Switch to Info, ensure throttling works and no battery spikes.
  3. Disable streaming, confirm indicator hides and no logs transmit.
  4. Break app-group access (simulate fallback) to confirm streaming still functions and diagnostic warnings appear.

## Rollout Notes
- Feature should remain off in production builds unless explicitly enabled (possible feature flag around the segmented control).
- Update developer documentation to explain how to enable streaming, where to view logs, and how to interpret the new diagnostics output.
