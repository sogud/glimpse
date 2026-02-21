# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PhotoSwipeCleaner is an iOS application built with SwiftUI that provides a Tinder-like interface for organizing photo libraries. Users swipe through photos to keep, delete, move to albums, or skip.

## Build Commands

Open and build in Xcode:
```bash
open PhotoSwipeCleaner.xcodeproj
```

Or build from command line:
```bash
xcodebuild -project PhotoSwipeCleaner.xcodeproj -scheme PhotoSwipeCleaner -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project Structure

```
PhotoSwipeCleaner/
├── App/                          # App entry point
│   └── PhotoSwipeCleanerApp.swift
├── Model/                        # Data models
│   └── PhotoAsset.swift          # Wrapper for PHAsset
├── View/                         # Main UI views
│   ├── ContentView.swift         # Main container with permission handling
│   ├── SwipeView.swift           # Gesture handling container
│   ├── PhotoCardView.swift       # Individual photo card
│   └── AlbumPickerView.swift     # Album selection sheet
├── ViewModel/
│   └── PhotoSwipeViewModel.swift # Main coordinator (@MainActor)
├── Service/
│   └── PhotoLibraryService.swift # PhotoKit wrapper
├── Core/Services/
│   ├── OnboardingManager.swift   # Onboarding flow state
│   └── HapticService.swift       # Haptic feedback
├── UI/Views/                     # Additional UI (Settings, Onboarding)
├── UI/Styles/Colors.swift        # Color definitions (dark mode support)
└── Utils/
    └── GestureDirection.swift    # Swipe direction detection
```

## Architecture

**MVVM Pattern** with clear separation:
- **Model**: `PhotoAsset` wraps `PHAsset` for SwiftUI compatibility
- **ViewModel**: `PhotoSwipeViewModel` manages state, uses `@MainActor` for thread safety
- **Service**: `PhotoLibraryService` encapsulates all PhotoKit operations
- **View**: SwiftUI views observe ViewModel state

## Key Implementation Details

### Swipe Gestures
- Threshold: 80 points for direction detection
- Right: Keep (green), Left: Delete (red), Up: Move to album (blue), Down: Skip (gray)

### Undo Support
Delete and move operations are undoable via the undo stack in `PhotoSwipeViewModel`.

### Permissions
Supports both full and limited photo library access (iOS 14+). Declared in `Info.plist`:
- `NSPhotoLibraryUsageDescription`: "需要访问您的相册来整理和删除照片"

### Onboarding Flow
5-step flow managed by `OnboardingManager`: Welcome → Gesture Tutorial → Permission → Analysis → Complete

## Development Requirements

- Xcode 16.2+
- iOS 18.2+ deployment target
- Swift 5.0+

## Code Style

- Use Chinese for all documentation comments (`///`)
- Mark private methods/properties explicitly
- Use `@MainActor` for async operations that update UI
- Keep Views stateless when possible

## References

- `AGENTS.md`: Detailed developer guide with common tasks
- `PRODUCT_DOC.md`: Product requirements document (Chinese)
