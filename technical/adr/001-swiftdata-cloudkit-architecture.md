# ADR 001: SwiftData + CloudKit Dual Architecture for iOS

## Status
Accepted

## Context
CareKeeper requires collaborative care tracking with offline-first capabilities. The iOS app needs to:
- Sync data across devices via CloudKit
- Support offline reads/writes
- Handle CloudKit sharing for multi-caregiver collaboration
- Maintain fast local data access
- Separate owned carees from shared carees

## Decision
Implement a dual ModelContainer architecture:
1. **Main Container**: SwiftData with CloudKit sync enabled (`cloudKitDatabase: .private()`)
2. **Cache Container**: Local-only SwiftData for fast offline reads

Data flow:
- Writes go to CloudKit via CloudKitDataService/CloudKitSharedDataService
- LocalCacheService maintains SwiftData cache with debounced refresh (0.25s)
- Views observe cache via Combine publishers (`@Published myCarees`, `sharedCarees`)

## Consequences

### Positive
- **Offline-first**: All reads use local cache, work offline
- **Reactive UI**: Combine publishers provide automatic view updates
- **Separation of concerns**: CloudKit services handle sync, cache handles reads
- **Fast queries**: SwiftData relationships enable efficient data traversal
- **Flexible sync**: Can batch updates and control sync timing

### Negative
- **Complexity**: Two data stores require synchronization
- **Memory overhead**: Duplicate data in main + cache containers
- **Cache invalidation**: Must carefully manage cache refresh timing
- **More code**: Additional services (LocalCacheService, CloudKitDataService, etc.)

### Alternatives Considered
1. **SwiftData only with automatic CloudKit sync**:
   - Less control over sync timing
   - Harder to distinguish owned vs shared data
   - No cache layer for offline reads

2. **Pure CloudKit without SwiftData**:
   - Loses SwiftData relationship traversal
   - More manual caching and query code
   - No automatic UI updates via @Query

## Related
- ADR 002: Direct CloudKit for watchOS (different approach for constrained environment)
- ADR 003: Infrastructure Encryption Only (security implications)
