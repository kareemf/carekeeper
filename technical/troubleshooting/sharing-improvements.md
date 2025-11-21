# Sharing Regression Analysis & Mitigation Plan

## Issues Observed

1. **Generic iCloud placeholder shown instead of CareKeeper branding**  
   - Our share metadata only writes the `CKShare.SystemFieldKey.title`. We never populate `thumbnailImageData` on the share nor supply a custom image via `UICloudSharingControllerDelegate`.  
   - The delegate in `CloudSharingView` implements only `itemTitle` and the success/failure hooks, so the system defaults to the generic iCloud icon even though our assets exist in the bundle.

2. **Accepted invites do not populate the recipient’s caree list immediately**  
   - When a share invite is accepted, `SceneDelegate` posts `.cloudKitShareAccepted`, but the observers only display a confirmation alert.  
   - Neither `CloudKitSharedRecordsService` nor `LocalCacheService` refresh in response, so the shared zones are not pulled down until a manual refresh or a push notification later triggers `fetchSharedCarees()`.

## Mitigation Plan

1. **Restore branded share thumbnails**
   - Add a CareKeeper share-logo asset that conforms to Apple’s recommended thumbnail size (PNG, square, ~90×90) and fall back to the existing app icon if it’s missing.  
   - Update `CloudKitSharingService.createOrGetShare` to attach `thumbnailImageData` (and optionally `thumbnailImageDataFileURL`) to the `CKShare` before saving so the metadata travels with the invite across platforms.  
   - Pass the `Caree` into `CloudSharingView` (as an optional to avoid cascading breakage) and extend the coordinator to implement `itemThumbnailImage`/`itemThumbnailData`, prioritizing the caree’s photo with automatic fallback to the share-logo asset so older shares gain the new branding without migration.  
   - Verify in-app by presenting the share sheet; then accept on another device to ensure the icon propagates.

2. **Refresh data after invite acceptance**
   - Introduce a dedicated observer (e.g., `ShareAcceptanceRefresher`) that listens for `.cloudKitShareAccepted`, cancels any pending refresh task, waits briefly for zone replication, then runs `sharedRecordsService.fetchSharedCarees()` with an exponential-backoff retry (1s/2s/3s) plus a cache refresh so we handle slow networks gracefully.  
   - If the shared records service isn’t readily accessible from the delegate layer, expose a static hook or use the existing `CloudKitSyncMonitor` to coordinate the refresh.  
   - Keep the debouncing logic so multiple notifications don’t stampede the network and add the retry guardrails advocated in the latest review.  
   - Provide user feedback by toggling the existing sync indicator or logging that the post-acceptance refresh has begun/completed.  
   - Add regression coverage: unit-test that the observer reacts to the acceptance notification, and include a manual QA checklist entry for “Accept invite ➝ shared caree appears without relaunch.”
