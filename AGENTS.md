# Glimpse Agent Guide

Read [README.md](README.md) for supported commands and [docs/functionality.md](docs/functionality.md) for the release scope and acceptance criteria. Native behavior is defined in [docs/macos-local-photo-classification-spec.md](docs/macos-local-photo-classification-spec.md). Native preview verification is separate from the standalone CLI release.

## Required development cycle

This is an internal project under development. Rewrite in-scope code toward the simplest correct design (KISS). Do not add backward compatibility, legacy format readers, migrations, duplicate state, or speculative abstractions. Never delete personal files or reset user progress as a test fixture.

For every behavior change, follow this cycle in order:

1. Update the relevant documentation first. Remove contradictory and outdated descriptions; define the public behavior and acceptance criteria.
2. Write a test through the public interface and run it to observe the intended failure. Use TDD in vertical slices: one failing behavior, then its implementation.
3. Make the smallest implementation that passes the test. Test persistence with temporary storage and Photos/model interactions at the system boundary.
4. Review the final code and documents together. Remove unnecessary code, compatibility branches, and duplicate documentation; run the relevant checks and resolve contradictions before delivery.

When commit, push, and release are requested, complete verification first and ship the verified artifact. Report the actual release scope; a CLI release does not certify the native applications.

## Surfaces and ownership

- CLI/ and Sources/PhotosCLIKit/: standalone macOS CLI, Photos Automation, LM Studio, JSON plans and batch progress. No dependency on the native App or SwiftData.
- MacApp/: native macOS PhotoKit task/review UI, LM Studio, album writes and undo.
- Sources/SmartCore/: native classification planning, task storage and local smart analysis.
- Sources/App/, Sources/View/, Sources/ViewModel/, Sources/Service/: iOS swipe-cleanup application.
- Tests/: Swift package tests, CLI checks and isolated HTTP fixtures.
- PhotoSort.xcodeproj: PhotoSort (iOS) and GlimpseMac (macOS) schemes.

CLI and native stores are separate. CLI progress does not prove native task or album-write success.

## Working rules

- Inspect branch/status first; preserve unrelated changes. Prefix shell commands with rtk.
- Keep code linear and maintainable. Follow the existing Chinese user-facing messages and documentation-comment style.
- Use @MainActor for native UI state; propagate cancellation before saving results or starting another request.
- Never access personal Photos as a test fixture. Use synthetic plans, temporary directories and injected command/network behavior.
- Classification must not implicitly mutate Photos. CLI apply requires a validated plan and explicit confirmation. “待删除” is a review album, not permission to delete.
- Model requests are loopback-only and must not follow redirects. CLI sends one inference request per photo; do not add silent retries/fallbacks.
- Use the current state format only. Old formats are not read or migrated; the CLI release uses a separate runtime directory so existing personal files are left intact.
- Save a new plan before advancing batch state; never overwrite an existing plan or reset personal progress for testing.
- Report partial writes honestly. Do not promise transactionality, rollback or recovery that has not been implemented and verified.

## Proportional verification

For CLI changes:

    rtk proxy bash scripts/check.sh

For HTTP changes (synthetic images and localhost server only):

    rtk proxy python3 Tests/CLITransportChecks.py

CLI builds need compatible Swift 6 Command Line Tools. Native builds need a full compatible Xcode. SmartCore uses SwiftData macros, so full swift test may not work in a Command-Line-Tools-only environment; don't confuse this with passing native tests. Run only checks related to the change and state what remains unverified. Prose changes need link/diff checks, not an app build.

## CLI releases

Use bash scripts/package-cli.sh vX.Y.Z to build and ad-hoc sign the macOS arm64 executable, package it with docs/cli-install.md, and produce SHA256SUMS under .build/releases/. Run python3 Tests/CLIReleaseChecks.py <release-directory> for archive contents, signature and isolated install checks. Download the uploaded assets and run the same check on them. CI must pass for the released code. Do not include runtime files, plans, photos, temporary exports or personal paths. Never use a CLI release to claim native UI/PhotoKit acceptance.

## Native previews

Build GlimpseMac with compatible full Xcode, configuration Release and ARCHS=arm64. Package only the App and docs/native-install.md using bash scripts/package-native.sh vX.Y.Z <built-app> <new-output-directory>. Run python3 Tests/NativeReleaseChecks.py <release-directory> before upload and on downloaded assets. The package is ad-hoc signed and must not contain debug user paths, task stores, photos or test fixtures. Use a prerelease until real-library and UI acceptance is complete; compile/archive checks are not interaction tests.
