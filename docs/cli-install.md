# Glimpse CLI internal development release

The release contains a macOS arm64 CLI for local Apple Photos classification with LM Studio. It does not contain a native App. The binary is ad-hoc signed; it is not notarized for App Store distribution.

Requirements: Apple Silicon Mac, macOS 14+, Photos, and a running local LM Studio vision model with structured output. No Xcode is needed for the downloaded CLI. If building from source, use compatible Swift 6 Command Line Tools and run `swift build -c release --product glimpse`.

Verify the downloaded archive against SHA256SUMS, extract it, and install the `glimpse` binary into your own PATH directory. Run `glimpse photos --help` first.

1. Start LM Studio's local server and load your vision model.
2. Run `glimpse photos classify-next --limit 10`. Allow your terminal to control Photos when macOS asks.
3. Review the returned JSON plan and classification reasons.
4. Run `glimpse photos apply "<plan.json>"`, review the album list, and enter `yes`.
5. Run `glimpse photos status --json` to inspect progress and persistent album receipts.

If a write fails or the process stops, repeat apply with the same unedited plan. Confirmed albums are skipped and the current album is checked for existing members. Do not edit receipt files. To retry analysis failures or export skips, run `glimpse photos retry failed` or `glimpse photos retry skipped`, then classify-next.

Runtime files live in `~/Library/Application Support/Glimpse/CLI`; use `GLIMPSE_HOME` to select another directory. This development version uses only its current data format and does not read or migrate old files. Starting in this directory does not carry forward old deduplication progress, so earlier photos may be analyzed again. Existing personal files are left intact.

Photos are temporarily exported and resized for loopback-only inference. Plans and receipts contain private IDs, filenames and reasons; keep the runtime directory private. “待删除” is a suggestion album. This CLI adds album memberships and never deletes photos or automatically rolls back writes.
