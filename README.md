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

## macOS Photos CLI 本地分类

不需要 Xcode。自动从上次进度继续处理下一批最多 10 张静态照片：

```bash
swift run glimpse photos classify-next --limit 10
```

如需只分析手动选择的照片，使用 `classify-selection`。

CLI 默认连接已运行的 `http://127.0.0.1:1234/v1`，自动选择 Qwen3-VL 等已加载视觉模型。每张照片只发送一次分类请求，由同一次响应确定普通照片/截图及具体分类。它会临时导出最长边 1024 px 的 JPEG 给本机 LM Studio，完成后删除临时文件，并把分类计划保存到 `~/Library/Application Support/Glimpse/Plans/`。分析阶段不会修改 Photos。

检查终端输出或计划 JSON 后，再显式应用：

```bash
swift run glimpse photos apply "<plan.json>"
```

首次运行时允许终端控制「照片」。批次进度按 Photos 的稳定资源 ID 保存，不受图库顺序变化影响；视频和 Photos 无法导出的项目会安全跳过，单张识别失败会重试，连续失败三次后停止自动重试并留在计划中待人工确认。应用后，原照片不会删除或移动，只会加入 `Glimpse` 文件夹下的“普通照片·分类”或“截图·分类”相册。模型可把明显误拍、严重失焦、空白或无信息价值的图片建议到统一的 `Glimpse/待删除` 相册，但 CLI 不提供删除照片的命令。

## Notes / 说明

- Some PhotoKit confirmations are controlled by iOS and cannot be fully removed. Batch deletion reduces repeated prompts.
- Limited Photos access (iOS “Select Photos…”) will only show the items you granted.
