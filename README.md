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
- Xcode 16.2+

## Build & Run / 构建运行

1. Open `PhotoSort.xcodeproj` in Xcode.
2. Select a device (real device recommended for PhotoKit behavior).
3. Build and Run.

## Notes / 说明

- Some PhotoKit confirmations are controlled by iOS and cannot be fully removed. Batch deletion reduces repeated prompts.
- Limited Photos access (iOS “Select Photos…”) will only show the items you granted.
