## Why

PhotoSort currently helps users make fast manual decisions through swipe sessions, but it does not help users understand where photo-library storage is going or which groups are worth reviewing first. A separate smart analysis tab can surface high-value local insights without changing the existing delete/archive workflow.

## What Changes

- Add a new top-level Smart tab alongside the existing cleanup experience.
- Analyze the user's photo library locally using PhotoKit metadata, Apple Vision, and deterministic rules.
- Surface storage and content insights such as large videos, large files, screenshots, document-like images, OCR-heavy images, and similar-photo groups.
- Present smart suggestions as reviewable groups that can lead into the existing cleanup flow later.
- Keep all first-stage analysis on device. Do not add cloud AI, uploaded image analysis, or custom model training.
- Do not automatically delete photos or automatically create albums without explicit user confirmation.

## Capabilities

### New Capabilities

- `smart-photo-analysis`: Local smart analysis of the photo library, including analysis state, insight groups, suggestion review, and future handoff into cleanup sessions.

### Modified Capabilities

None.

## Impact

- App shell: introduce a tabbed root after onboarding while preserving the existing cleanup flow.
- Photo analysis: add local analysis services for PhotoKit metadata, file sizes, Vision classification/OCR/similarity, and rule-based grouping.
- Persistence: add storage for analysis results, scan progress, model/rule versions, and cached group membership.
- UI: add Smart tab screens for scan state, insight cards, group detail, and user actions.
- Privacy: keep v1 analysis fully local and avoid cloud model dependencies.
