# watchOS Caree Photo Caching Plan

## Context
Images are currently large (1.5 – 5 MB) because they aren’t downscaled yet. 
Downscaling will be implemented, but even after that, photo updates will likely be uncommon. 
So we can aggressively cache photos to reduce watch bandwidth and CPU consumption.

## Goals
- Reduce repeated large asset transfers for caree photos on watchOS.
- Keep the watch experience responsive while providing a clear way to refresh images when they change.

## Scope
- Applies to caree photo assets shown on watchOS (CareeListView, detail header, etc.).
- Includes UX messaging on iOS Caree editing so users know how to refresh the watch after updating a photo.

## Approach
1. **Cache-first photo access on watchOS**
   - Store the fetched caree image in the existing app-group cache (same lifecycle as other snapshots).
   - When loading carees:
     - Use `desiredKeys` to exclude the image asset field on the routine fetch.
     - If the cache already holds an image for the caree, reuse it.
     - If no cached image exists, perform a one-time follow-up fetch for that caree’s photo and persist the result.
2. **Manual refresh path**
   - When users trigger the refresh button or pull-to-refresh, perform a full fetch that includes the photo field so updates from other devices propagate immediately.
   - After each forced refresh, update the cached image (including change token metadata so we can detect future differences if needed).
3. **UX messaging**
   - iOS `CareeEditView`: whenever the user picks a new photo, display: “Watch app users: perform a manual refresh to load the new image.”
   - Documentation: add an `!!! note` to the watch user guide and FAQ describing the aggressive caching strategy and the refresh workaround.
4. **Downsampling**
   - Downscale the caree photo during upload on iOS so future fetches (including the watch cache) receive a smaller asset. Existing photos remain untouched; new uploads automatically use the smaller representation.

## Edge Cases & Handling
- If the follow-up photo fetch fails, fall back to placeholder imagery and log a warning; subsequent refresh attempts can retry.
- When a caree photo is removed on iOS, clear the cached image on watch during the next forced refresh.

## Testing
- Edit a caree photo on iOS, verify:
  - Watch still shows cached image until manual refresh.
  - After tapping the refresh button, the new photo appears.
  - Documentation and banner text guide the user appropriately.
- Validate cold launch behavior: first visit to a caree with no cached photo downloads it once, subsequent visits reuse cache.
