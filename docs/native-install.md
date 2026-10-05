# GlimpseMac internal preview

This package contains a native AppKit application without SwiftUI or a Web interface. PhotoKit reads Apple Photos; image inference uses only a local LM Studio server. It is a development preview, not a completed real-library production acceptance.

Requirements: Apple Silicon, macOS 15+, and LM Studio 0.4+ with a loaded vision model and its local server running. The downloaded App does not require Xcode. The App is ad-hoc signed and not notarized; macOS may require you to approve opening it through the standard security UI. Do not disable system protections.

Verify the ZIP against SHA256SUMS, extract it, and move GlimpseMac.app to your preferred applications directory. Launch it and allow Photos access only when you choose to use it. Limited access restricts classification to the photos you allow.

1. Start LM Studio's local server and load your downloaded vision model.
2. Refresh the model status in Glimpse. Downloaded models without a loaded instance are not ready for classification.
3. Choose the next whole-library batch, an album or a date range. Start with 10 photos; larger batches can contain 50 or 100.
4. Create the task, then start classification. Pause or continue the fixed batch as needed.
5. Review photo categories and the per-photo album-write checkboxes. Explicitly choosing an unclassified result removes its write approval.
6. Review the target albums and the confirmation sheet, then confirm writing. Analysis alone does not modify albums.

The suggested-deletion album contains candidates for human review; the App never deletes photos. Undo removes only album memberships recorded as newly added by this task. Interrupted writes or undo operations require inspection in Photos, after which the task can only be closed, not automatically retried.

Native task data lives in the system Application Support directory under Glimpse/Native/Tasks.store. Sandboxed builds use their application container. The directory must be private to the current user. New native settings and tasks do not import CLI or older native progress; existing files are preserved, so previously analyzed photos may be analyzed again. There is no compatibility layer or migration.

PhotoKit obtains a resized image in memory and may download an iCloud original through the system. Photos and OCR are not uploaded to cloud inference or telemetry. Task records contain private photo identifiers and reasons; do not share the data directory.

Automated checks cover batch selection, task progress, HTTP model metadata, native compilation, isolated storage and AppKit control interactions with synthetic tasks, including cancelling album writes. They do not prove current-model accuracy, real Photos permissions/iCloud behavior, full-library performance or complete application integration.
