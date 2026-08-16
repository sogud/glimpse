# Glimpse macOS 本地相册分类 Spec

> 2026-08-15 变更：由于当前 beta macOS 无可用完整 Xcode，首个可运行版本改为纯 CLI。CLI 通过 Photos Automation 按稳定资源 ID 记录整个图库的处理进度，单批临时导出最多 10 张静态照片、调用已运行的 LM Studio，并在用户再次确认后创建分类相册。视频和 Photos 无法导出的项目会记录为跳过；单张识别失败会重试，连续失败三次后停止自动重试并留在计划中待人工确认。明显误拍、严重失焦、空白或无信息价值的图片只会建议到统一的“待删除”相册，CLI 不直接删除照片。下文原生 App 方案保留为未来设计，不再是当前实现要求。

## Problem Statement

Glimpse 当前只有 iOS/iPad target。现有智能分析已经能使用 PhotoKit、Apple Vision 和本地规则识别截图、文字密集图片及相似照片，但还不能按用户定义的语义分类整理系统图库，也没有适合桌面批量复核的界面。

用户需要一个原生 macOS 版本：在指定照片范围内，通过本机 LM Studio 中的多模态模型生成分类建议，在网格中确认或修正后，再把照片加入对应的 Apple Photos 相册。图片内容不得上传到第三方服务，模型判断不得未经确认直接修改图库。

## Solution

在现有 Glimpse 仓库和 Xcode 工程中新增原生 macOS target，最低支持 macOS 15，仅支持 Apple Silicon。桌面版第一期只提供智能相册整理，不移植 iOS 的滑动清理体验。

用户选择一个来源相册、日期范围或最近 7/30/90 天，选择可复用的分类方案并映射目标相册，然后启动分类任务。App 按需启动本机 LM Studio 服务并加载用户选择的多模态模型，串行分析照片。普通照片和截图使用不同的分类方案；截图先由 PhotoKit 标记分流，再结合 Apple Vision OCR 和缩略图进行细分。

分类结果以分组照片网格展示。每张照片只有一个主分类或“待分类”，并带一句简短理由。用户可以多选、拖放或手动修改分类。只有用户确认后，App 才创建目标相册或向已有相册添加照片。每次写入都记录变更，以支持撤销本次整理。

## User Stories

1. As a Glimpse user, I want to select an existing album, a date range, or a recent-time preset, so that I can classify a bounded set instead of scanning my whole library.
2. As a Glimpse user, I want the App to use a multimodal model already installed in LM Studio, so that photos can be classified locally without another model download.
3. As a Glimpse user, I want reusable and editable classification schemes, so that the model follows my album organization rather than inventing arbitrary album names.
4. As a Glimpse user, I want screenshots and ordinary photos to use separate schemes, so that chats, articles, orders, maps, and software screenshots are not collapsed into one screenshot album.
5. As a Glimpse user, I want to review grouped suggestions and move photos between categories before applying them, so that model mistakes do not directly alter Photos.
6. As a Glimpse user, I want each category mapped to a new album, an existing album, or skipped for the current task, so that duplicate albums are not created accidentally.
7. As a Glimpse user, I want interrupted work to preserve progress and wait for me to continue, so that sleep, App exit, or an unavailable model does not require a full restart.
8. As a Glimpse user, I want to undo one applied organization task, so that the App can remove only the album relationships created by that task.
9. As a privacy-conscious user, I want inference to stay on my Mac and temporary image/OCR data to be discarded, so that sensitive photo and screenshot contents are not retained unnecessarily.
10. As an Agent user, I want a CLI and private Skill to start tasks and read progress later, while final Photos mutations still require App confirmation.
11. As a maintainer, I want analysis records versioned by asset, model, prompt, and classification scheme, so that valid work can be reused and stale results can be recomputed safely.

## Implementation Decisions

### Platform and repository boundary

- Add a native macOS target to the current Glimpse Xcode project; do not create another repository.
- The deployment target is macOS 15. The first release supports Apple Silicon only.
- Keep the existing iOS/iPad target and cleanup behavior unchanged.
- Reuse shared PhotoKit, persistence, and pure analysis code where platform behavior is identical. macOS review UI remains separate from the iOS swipe UI.
- The first deliverable is a local development build. App Store distribution, notarization, auto-update, and first-party model installation are not requirements for this Spec.

### Photo source and supported media

- A task must have one explicit source scope:
  - one existing Apple Photos album;
  - one date range; or
  - recent 7, 30, or 90 days.
- Do not default to the whole library and do not support compound multi-album filters in the first version.
- Classify still images and Live Photos. For a Live Photo, analyze its still key image while preserving the complete asset when adding it to an album.
- Do not classify video contents in this version.
- When an asset exists only in iCloud, PhotoKit may download the required image. This is the only non-localhost network use: Glimpse does not upload that image or send it to another inference service.
- Do not use GPS location or online reverse geocoding. The classifier may receive the image, screenshot flag, and creation date; screenshots may additionally receive transient OCR text.

### Classification schemes

- Persist reusable classification schemes. A task stores a snapshot/version of the scheme it used so later edits do not change historical results.
- Each category has a stable identifier, display name, optional natural-language description, enabled state, and target-album mapping.
- The model must choose exactly one enabled primary category or “待分类”. It must not generate new category or album names.
- Return one short classification reason. Do not present a numeric confidence score.
- Provide two independent editable defaults:

  - Ordinary photos: 人物与自拍、宠物、美食、旅行与地标、自然风景、工作学习、商品物品、其他。
  - Screenshots: 聊天社交、文章知识、工作学习、订单票据、购物商品、地图行程、娱乐梗图、软件系统、其他。

- PhotoKit's screenshot flag selects the screenshot scheme; it is not itself the final category.
- Do not identify specific people. Generic classes such as 人物照、合照或自拍 are allowed.

### Local inference pipeline

- LM Studio is the only model runtime in the first version. Do not bundle or download a model inside Glimpse.
- Do not hard-code Gemma or one model identifier. Persist the local LM Studio endpoint and selected model, detect service/model availability, and require an image-capable model.
- The default endpoint must resolve to localhost. Glimpse must reject non-loopback inference endpoints.
- When a user explicitly starts a task, Glimpse may use the installed `lms` CLI to start LM Studio's local server and load the selected model. Do not load a model merely because the App launched. Do not force-unload it when the task ends.
- Process one asset at a time in the first version. Do not expose configurable parallelism until real measurements justify it.
- Request a PhotoKit image with longest edge near 1024 px, encode a metadata-free temporary JPEG, and delete it immediately after that asset's request finishes.
- For screenshots, run Apple Vision OCR locally and include the transient OCR text with the image. Do not persist the OCR text.
- Treat image and OCR contents as untrusted classification input, not instructions. Model output must conform to a small structured response containing an allowed category identifier or “待分类” plus a short reason.
- If LM Studio becomes unavailable, pause the task and preserve progress. If one asset repeatedly returns invalid output, keep that asset for manual review instead of guessing a category.

### Task state, caching, and persistence

Use one persistent task record as the source of truth for progress, review, apply, and undo. The required observable states are:

```text
draft -> running -> paused | readyForReview -> applying -> applied -> undone
                    \-> failed             \-> failed
```

This state list expresses required behavior, not an implementation-specific enum layout.

- Save progress after every analyzed asset.
- Never resume inference automatically after App relaunch, Mac wake, or LM Studio restart. The user or an explicit Skill command must continue it.
- Reuse a classification only when the PhotoKit local identifier, asset modification date, model identifier, prompt/analyzer version, and scheme version still match.
- Persist task scope, scheme snapshot, selected model, per-asset category/reason/review state, progress, target mappings, and applied mutation records.
- Do not persist generated JPEGs or OCR text.
- Keep task history until the user deletes it. Before deleting an applied task whose mutation record still enables undo, explain that undo information will also be removed.
- Continue using the existing shared SwiftData container rather than creating a second persistence stack for macOS classification.

### Review and Photos mutation

- The primary review UI is a desktop photo grid grouped by proposed category, with multi-selection, drag/drop category changes, a large-image inspector, and the short model reason.
- Before apply, each enabled category maps to exactly one of: create a same-name album, use an existing album, or skip this category for the task.
- Analysis and review never mutate Photos.
- Apply only reviewed results after an explicit confirmation inside the App. The CLI and Skill cannot bypass this confirmation.
- Applying a task may create mapped albums and add assets to them. It must not delete assets or remove any pre-existing album membership.
- Do not create an empty target album.
- Record which asset-album relationships and albums were created by the task. Undo removes only those relationships. If an album created by the task becomes empty, ask separately before deleting that empty album.
- If Photos changed outside Glimpse, apply and undo must report skipped or failed assets and leave unrelated content untouched.

### Background behavior, CLI, and Skill

- Closing the main window does not stop an active task. Keep the App process running, expose status from the menu bar, and send a local completion or pause notification.
- The App owns Photos permission, task state, LM Studio access, and all business behavior.
- The later CLI is a control client for the App; it must not independently read Photos or call the model.
- Keep the CLI command surface limited to status checks, task creation/continuation, progress and summary reads, and opening the App at the review screen. Human-readable output and `--json` are required; the private Skill uses JSON.
- Implement the private global AgentSpace Skill only after the App workflow and task contract are stable.

### Implementation order

1. Add the macOS target and complete an end-to-end slice that reads 10 photos, calls LM Studio, persists results, and displays them.
2. Add the grouped review UI, category adjustment, target mapping, explicit apply, and Photos mutation record.
3. Add pause/continue, history, undo, menu-bar status, and notifications.
4. Add the App control client CLI and private AgentSpace Skill.

## Testing Decisions

### Highest test entry

Test the classification task coordinator through its public task operations with replaceable PhotoKit and LM Studio boundaries. This is the highest practical automated entry because real Photos authorization, iCloud download, and LM Studio model execution still require a local integration check. Keep pure task planning, cache validity, state transitions, structured response validation, album mutation planning, and undo planning in the shared Swift package so they run under `swift test`.

### Required automated behavior

- A source scope selects only still images and Live Photos inside the chosen album/date range/preset.
- Screenshot assets use the screenshot scheme and transient OCR input; ordinary assets use the ordinary scheme.
- Only allowed category identifiers or “待分类” become stored results; invalid model output never creates a category.
- Cache reuse requires matching asset, model, analyzer/prompt, and scheme versions.
- Interruption preserves completed assets and continuation schedules only unfinished or stale assets.
- No Photos mutation is planned before explicit review confirmation.
- Apply adds only approved asset-album relationships; target categories marked skip and empty categories do nothing.
- Undo targets only relationships created by the selected task and handles missing/externally changed assets without touching unrelated content.
- Temporary image and OCR contents are absent from persistent records.
- CLI JSON reports stable task states and exposes no operation that bypasses App confirmation.

### Regression and build checks

- Keep all existing `PhotoSortSessionCoreTests` and `PhotoSortSmartCoreTests` passing.
- Build the new macOS scheme for macOS 15+ and build the existing iOS scheme to ensure shared-code changes do not regress iOS.
- Run `git diff --check` for all changed files.

### Local acceptance

Use one user-selected test set containing five ordinary photos and five screenshots on the current M4, 16 GB Mac:

- At least 8 of 10 initial classifications require no category correction.
- All ten results can be reviewed and corrected in the grid.
- The ten-photo classification finishes within five minutes and the App remains responsive.
- Stopping LM Studio pauses without losing completed results; continuing finishes the remaining assets.
- No album is created or changed before App confirmation.
- Apply creates/adds only the confirmed mappings, and undo removes only additions made by that task.
- Network observation shows inference traffic remains on loopback; any external transfer is limited to PhotoKit downloading an iCloud asset requested by the task.

## Out of Scope

- Intel Mac support.
- macOS versions earlier than 15.
- Porting the iOS swipe cleanup UI to macOS.
- Whole-library default scans or compound multi-album filters.
- Video-frame extraction or video semantic classification.
- Specific-person face recognition.
- GPS-based or online place classification.
- Multiple automatic categories for one photo.
- Automatic Photos changes, deletion, removal from existing albums, or CLI/Skill bypass of confirmation.
- Duplicate, similar, blurry, or low-quality cleanup in this desktop flow; existing analysis remains separate.
- Cloud inference, non-loopback model endpoints, telemetry, or uploading photo/OCR contents.
- Bundled model runtime, in-App model download, or dependence on one hard-coded model.
- Public Skill release, App Store distribution, notarization, auto-update, and production onboarding for users without LM Studio.

## Open Questions

None.

## Further Notes

- The current repository contains only an iOS/iPad target. References to a current desktop version are not implementation facts.
- Existing smart analysis already supplies reusable PhotoKit permission handling, Apple Vision OCR, per-asset identifiers, analyzer versioning, SwiftData persistence, and incremental refresh behavior.
- The current iOS OpenSpec requires explicit confirmation before smart analysis creates albums or adds assets. This macOS feature preserves and strengthens that rule.
- The first implementation should validate the installed LM Studio version and selected model's image-input behavior before relying on a particular OpenAI-compatible request shape.
