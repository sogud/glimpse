## Context

PhotoSort's current primary experience is a SwiftUI cleanup flow owned by `ContentView` and `PhotoSwipeViewModel`. It already knows how to request photo-library access, fetch PhotoKit candidates by preset, estimate file sizes through `PhotoAsset`, mark delete candidates, batch-delete after system confirmation, and add assets to user albums.

The smart analysis feature should sit beside that flow rather than inside it. The goal is to help users decide which sets of photos are worth reviewing before they start swiping. The first version should stay fully local: PhotoKit for metadata and file resources, Apple Vision for image understanding, and deterministic rules for grouping. Cloud AI, uploaded images, and custom-trained models are intentionally out of scope.

The app currently routes from `RootView` to either onboarding or `ContentView`. Introducing a Smart tab means the post-onboarding root should become an app shell that hosts cleanup and analysis tabs. The real swipe session can still preserve its immersive full-screen behavior by hiding or avoiding tab chrome while the session is active.

```text
RootView
  ├─ OnboardingView
  └─ MainTabView
       ├─ Cleanup tab -> existing cleanup experience
       └─ Smart tab   -> local analysis dashboard
```

## Goals / Non-Goals

**Goals:**

- Add a top-level Smart tab that does not regress the existing cleanup flow.
- Build a local analysis pipeline that can scan PhotoKit assets incrementally.
- Cache analysis results and scan progress so large libraries do not require full rescans on every launch.
- Produce reviewable insight groups for storage, screenshots, videos, document-like images, OCR-heavy images, and similar photos.
- Make smart groups eligible for future handoff into the existing cleanup session model.
- Keep user trust high by never deleting assets or creating albums automatically.

**Non-Goals:**

- No cloud AI or image upload in the first version.
- No custom model training in the first version.
- No bundled third-party Core ML model in the first version.
- No automatic deletion.
- No automatic album creation without explicit confirmation.
- No replacement of the existing swipe-based cleanup experience.

## Decisions

### Use a Separate App Shell for Tabs

Introduce a `MainTabView` after onboarding and keep the existing cleanup experience as one tab. The Smart tab gets its own view, state, and services.

Rationale: This isolates analysis complexity from the swipe flow. It also lets users treat analysis as optional, while preserving the current cleanup entry points and gestures.

Alternatives considered:

- Embed smart analysis inside `ContentView`: rejected because `ContentView` is already responsible for permission, session state, swipe chrome, settings, and completion states.
- Replace cleanup with a dashboard-first design: rejected because the manual swipe flow is the proven core interaction.

### Keep Analysis Local in v1

Use PhotoKit metadata/resource access and Apple Vision requests for classification, OCR, and similarity. Do not send user photos or thumbnails to an external service.

Rationale: Local analysis fits the privacy expectations of a photo-cleanup app, avoids API cost, works offline, and matches the user's stated preference to avoid model waste.

Alternatives considered:

- Cloud vision models: deferred because they add upload consent, cost, latency, and privacy complexity.
- Custom Core ML training: deferred because the product has not yet proven which categories need custom accuracy.
- Bundled open-source Core ML model: deferred until Vision and local rules show a real gap.

### Split Analysis into Metadata, Vision, and Rules

Model the pipeline as three composable stages:

```text
PhotoKit Asset
  ├─ Metadata Analyzer: size, type, dimensions, duration, date, screenshot flag
  ├─ Vision Analyzer: labels, OCR text hints, feature print, document/person signals
  └─ Rule Engine: large videos, screenshots, documents, similar groups, suggestions
```

Rationale: Many useful insights do not need Vision. Keeping metadata separate makes the first scan faster and allows the UI to show partial results while heavier analysis continues.

Alternatives considered:

- One monolithic analyzer: rejected because cancellation, progress reporting, caching, and future model versioning become harder.
- Vision-first scan: rejected because it wastes work on assets where metadata alone is enough.

### Persist Analysis Results with Versioning

Store per-asset analysis records keyed by `PHAsset.localIdentifier`, with timestamps and analyzer version fields. Store derived groups separately from raw per-asset facts.

Rationale: Large libraries require incremental scanning. Versioning lets the app invalidate only stale results when rules or Vision handling changes.

Possible storage options:

- SwiftData: good Swift-native fit for iOS 18.2+, queryable, and maintainable.
- SQLite: more explicit control and predictable performance.
- UserDefaults: rejected because analysis records and group membership will outgrow simple key-value storage.

The implementation can choose SwiftData unless build constraints or query performance suggest SQLite.

### Use Reviewable Smart Groups

Smart analysis should produce groups like `Large Videos`, `Screenshots`, `Documents`, and `Similar Photos`. A group detail screen should show member assets and a clear action surface. Any destructive or library-mutating action must require explicit user confirmation.

Rationale: AI-like features can damage trust if they feel automatic. Reviewable groups keep the app's decision model human-centered.

Alternatives considered:

- Auto-delete low-quality assets: rejected because false positives are unacceptable.
- Auto-create albums immediately: rejected because PhotoKit mutations should be user-driven.

### Plan for Cleanup Handoff Without Requiring It in v1

The Smart tab should expose group identifiers and asset identifiers in a shape that can later start a cleanup session from a smart group. The first implementation may display the group and defer the actual handoff if session architecture needs a separate coordinator.

Rationale: A direct handoff is valuable, but it should not force risky rewiring of `PhotoSwipeViewModel` in the first slice.

Alternatives considered:

- Share a single `PhotoSwipeViewModel` between all tabs immediately: possible, but it couples analysis work to cleanup state before the handoff design is proven.
- Duplicate cleanup state inside Smart tab: rejected because it would fork business logic.

## Risks / Trade-offs

- Large-library scanning can drain battery or make the app feel busy -> run incrementally, cap concurrent Vision work, expose pause/resume state, and prioritize metadata-only insights first.
- Vision classifications may be noisy -> treat labels as suggestions, combine them with rules, and show reviewable groups instead of automatic actions.
- Similar-photo grouping can be expensive -> compute feature prints lazily or in batches, cache results, and limit first-version grouping to a bounded recent window if needed.
- Limited Photos permission can make analysis incomplete -> clearly scope results to accessible assets and provide a path to manage photo access.
- Tab chrome may conflict with the existing full-screen swipe session -> hide or bypass tab chrome while a cleanup session is active.
- Analysis cache can become stale when the photo library changes -> observe library changes where possible and invalidate affected asset/group records.

## Migration Plan

1. Add the post-onboarding tab shell while keeping the existing cleanup tab behavior intact.
2. Add local analysis models and persistence behind a feature-local service.
3. Implement metadata scanning first so the Smart tab can show useful storage insights quickly.
4. Add Vision analysis in cancellable batches.
5. Add rule-based groups and group detail screens.
6. Add optional handoff into cleanup sessions only after the Smart tab can reliably produce stable asset groups.

Rollback strategy: the Smart tab can be disabled by returning `RootView` to the existing `ContentView` path and leaving analysis persistence unused. The feature should not mutate photo assets unless a user confirms an explicit action.

## Open Questions

- Should the first scan cover the full accessible library, the most recent N assets, or a user-selected scope?
- Should similar-photo grouping be v1 or v1.1 if Vision feature-print cost is high on real devices?
- Should analysis persistence use SwiftData or a small SQLite layer?
- Should Smart group handoff into cleanup be included in the first implementation slice or designed as a follow-up?
