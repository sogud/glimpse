## 1. App Shell

- [x] 1.1 Add a post-onboarding `MainTabView` with Cleanup and Smart tabs.
- [x] 1.2 Move the existing `ContentView` into the Cleanup tab without changing its current behavior.
- [x] 1.3 Ensure active swipe sessions keep their full-screen interaction model and do not suffer from tab chrome overlap.
- [x] 1.4 Verify onboarding still routes to the main app after completion.

## 2. Analysis Models and Persistence

- [x] 2.1 Define per-asset analysis models keyed by `PHAsset.localIdentifier`.
- [x] 2.2 Define smart insight group models with stable group identifiers and member asset identifiers.
- [x] 2.3 Choose and wire persistent storage for analysis records, scan progress, analyzer versions, and group membership.
- [x] 2.4 Add cache invalidation for analyzer version changes.
- [x] 2.5 Add stale-asset handling when a previously analyzed asset is no longer available from PhotoKit.

## 3. Metadata Analysis

- [x] 3.1 Implement PhotoKit asset enumeration for the authorized or limited library scope.
- [x] 3.2 Extract media type, creation date, dimensions, video duration, screenshot subtype, and local identifier.
- [x] 3.3 Reuse or adapt existing file-size resolution logic for exact or best-effort asset sizes.
- [x] 3.4 Add incremental scan progress reporting for metadata analysis.
- [x] 3.5 Add cancellation or pause behavior so scanning can stop cleanly when the Smart tab disappears or the app backgrounds.

## 4. Vision Analysis

- [x] 4.1 Add a local Vision analyzer for text recognition on image assets.
- [x] 4.2 Add a local Vision analyzer for image classification labels with confidence thresholds.
- [x] 4.3 Add a local Vision analyzer for similar-photo feature data or equivalent similarity signals.
- [x] 4.4 Run Vision work in bounded batches so UI responsiveness and battery use stay controlled.
- [x] 4.5 Persist Vision results separately from metadata results so metadata-only insights can appear first.

## 5. Rule Engine and Groups

- [x] 5.1 Implement large-video grouping from media type, duration, and file size.
- [x] 5.2 Implement large-file grouping from file size.
- [x] 5.3 Implement screenshot grouping from PhotoKit screenshot subtype.
- [x] 5.4 Implement document-like or OCR-heavy grouping from Vision text results.
- [x] 5.5 Implement similar-photo grouping from Vision similarity signals.
- [x] 5.6 Exclude low-confidence Vision results from automatic group membership.
- [x] 5.7 Hide empty groups and recalculate group summaries after assets disappear or cache entries invalidate.

## 6. Smart Tab UI

- [x] 6.1 Add a Smart dashboard with permission, empty, scanning, completed, and error states.
- [x] 6.2 Show scan progress and a retry path for recoverable scan failures.
- [x] 6.3 Display storage-oriented groups with count and estimated size.
- [x] 6.4 Display content-oriented groups with count and clear local-analysis language.
- [x] 6.5 Add group detail screens that show member assets and summary metadata before any action.
- [x] 6.6 Ensure long group names, counts, and size labels fit without truncation or unwanted wrapping on iPhone-sized screens.

## 7. User Actions and Safety

- [x] 7.1 Ensure Smart analysis never deletes assets automatically.
- [x] 7.2 Ensure Smart analysis never creates albums or adds assets to albums without explicit user confirmation.
- [x] 7.3 Add disabled or placeholder cleanup-handoff UI if full handoff is deferred.
- [x] 7.4 If cleanup handoff is included, pass stable asset identifiers into the cleanup session layer without duplicating swipe business logic.
- [x] 7.5 Omit unavailable assets from group details and handoff payloads.

## 8. Verification

- [x] 8.1 Typecheck all Swift sources.
- [ ] 8.2 Build and run the app on the configured iOS simulator.
- [ ] 8.3 Verify Cleanup tab preserves the existing quick-delete and archive entry flows.
- [ ] 8.4 Verify Smart tab permission, scanning, completed, group detail, and retry states.
- [ ] 8.5 Verify local analysis still works with network disabled.
- [x] 8.6 Verify no photo-library mutation occurs from Smart tab without explicit confirmation.
