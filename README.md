# PhotoSort (PhotoSwipeCleaner)

一个 iOS 照片清理工具：用滑动快速做决定，删除操作先“标记待删除”，最后一次性提交给系统相册确认。

This is an iOS photo cleanup tool: swipe to decide quickly. Deletions are staged first and then committed in one batch confirmation.

## Features / 功能

- Delete-first workflow: swipe left to mark for deletion, then batch delete once.
- Optional organize workflow: swipe right to move to a target album.
- Candidate presets: Screenshots, Videos, Recent 30 days (plus an advanced album source).
- Undo for the last action in a session.
- File size chip on cards (fetches from iCloud when needed, without blocking swipes).

## Privacy / 隐私

- Photos stay on device. The app uses PhotoKit and does not upload your media.
- Deletions go to the system “Recently Deleted” album, where you can recover them.

## Requirements / 环境

- iOS 18.2+
- macOS 15+（Apple Silicon，仅本地开发版本）
- Xcode 16.2+

## Build & Run / 构建运行

1. Open `PhotoSort.xcodeproj` in Xcode.
2. Select a device (real device recommended for PhotoKit behavior).
3. Build and Run.

## macOS 本地相册分类

1. 在 LM Studio 下载一个支持图片输入的模型。
2. 在 Xcode 选择 `GlimpseMac` scheme 并运行。
3. 授权 Apple Photos，选择相册、日期范围或最近 7/30/90 天。
4. 分类完成后在照片网格中调整结果，确认后才会写入目标相册。

App 默认连接 `http://127.0.0.1:1234/v1`，会在任务开始时通过 `lms` CLI 启动服务并加载模型。照片只发送给本机 LM Studio；仅当资源位于 iCloud 时，Photos 会先下载所需图片。

Agent/CLI 控制入口：

```bash
swift run glimpse status --json
swift run glimpse create-recent 7
swift run glimpse continue <task-id>
swift run glimpse review <task-id>
```

CLI 不能写入、删除或撤销相册变更；这些操作必须在 App 中确认。

## Notes / 说明

- Some PhotoKit confirmations are controlled by iOS and cannot be fully removed. Batch deletion reduces repeated prompts.
- Limited Photos access (iOS “Select Photos…”) will only show the items you granted.
