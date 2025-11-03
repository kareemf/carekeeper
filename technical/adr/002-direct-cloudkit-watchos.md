# ADR 002: Direct CloudKit with Snapshots for watchOS

## Status
Accepted

## Context
watchOS has severe memory constraints (~30MB typical, ~50MB max) compared to iOS (~200-400MB). The iOS dual-container SwiftData architecture would be too memory-intensive for watchOS. Requirements:
- Display carees and recent activities (24-hour window)
- Track new activities with Digital Crown input
- Minimize memory footprint
- Avoid accidental relationship traversal (memory spikes)
- Share code with iOS where possible

## Decision
Implement a direct CloudKit architecture with immutable snapshots:
1. **No SwiftData**: Skip ModelContainer initialization entirely
2. **WatchDataProvider**: Single data source with lazy loading
3. **SelectiveCloudKitService**: Aggressive query limits (24h, 100 activities max)
4. **Immutable Snapshots**: CareeSnapshot, ActivityTypeSnapshot, ActivitySnapshot
5. **Manual Cache Management**: Explicit `clearUnusedCache()` and `clearAllCache()` methods

Loading strategy:
- Carees: Eager (small dataset, ~20 typical)
- Activity types: On-demand when user opens caree detail
- Activities: On-demand with 24-hour window, 100 max per caree
- Clear cache on view disappear

## Consequences

### Positive
- **Low memory**: ~15-20MB typical usage (vs 40-50MB with SwiftData)
- **Predictable**: No relationship traversal, all loads explicit
- **Fast initial load**: Only carees loaded upfront
- **Better crash recovery**: Smaller memory footprint = fewer memory warnings
- **Clear cache lifecycle**: Explicit cache management tied to views

### Negative
- **Limited history**: Only 24 hours of activities (vs full history on iOS)
- **Manual cache management**: Developer must call clearCache methods
- **Code duplication**: Separate data layer from iOS
- **No automatic updates**: Must manually refresh after mutations
- **Optimistic UI complexity**: All mutations show immediately, sync in background

### Alternatives Considered
1. **Use iOS SwiftData architecture**:
   - Memory footprint too high (40-50MB typical)
   - Frequent memory warnings and crashes
   - Relationship traversal causes unpredictable memory spikes

2. **Use Core Data without SwiftData**:
   - Still requires ModelContainer
   - Less efficient than direct CloudKit for watch use case
   - Adds persistence complexity for limited benefit

3. **Use watch connectivity to fetch from iOS**:
   - Requires iOS app running
   - Higher latency
   - Doesn't work when phone not nearby

## Related
- ADR 001: SwiftData + CloudKit Dual Architecture (iOS approach)
- ADR 005: Snapshot Pattern for watchOS (implementation details)
