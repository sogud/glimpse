# PhotoSwipeCleaner - Agent Guide

## Project Overview

**PhotoSwipeCleaner** (照片滑动整理器) is an iOS application built with SwiftUI that helps users quickly organize their photo library using intuitive swipe gestures. The app provides a Tinder-like interface for photo management where users can:

- **Swipe Right**: Keep the photo
- **Swipe Left**: Delete the photo
- **Swipe Up**: Move the photo to a specific album
- **Swipe Down**: Skip and handle later

The app is designed with a clean MVVM architecture and supports both full and limited photo library access permissions on iOS.

## Technology Stack

- **Platform**: iOS 18.2+
- **Language**: Swift 5.0+
- **UI Framework**: SwiftUI
- **Frameworks Used**:
  - `Photos` / `PhotoKit` - System photo library access
  - `Combine` - Reactive programming for data binding
  - `UIKit` - Haptic feedback and some UI utilities

## Project Structure

```
PhotoSwipeCleaner/
├── App/
│   └── PhotoSwipeCleanerApp.swift    # App entry point (@main)
├── Model/
│   └── PhotoAsset.swift              # Wrapper for PHAsset with ObservableObject
├── View/
│   ├── ContentView.swift             # Main container view with permission handling
│   ├── SwipeView.swift               # Gesture handling container for photo cards
│   ├── PhotoCardView.swift           # Individual photo card with overlay indicators
│   └── AlbumPickerView.swift         # Album selection sheet for move operations
├── ViewModel/
│   └── PhotoSwipeViewModel.swift     # Main coordinator between Service and Views
├── Service/
│   └── PhotoLibraryService.swift     # PhotoKit wrapper for permissions and operations
├── Utils/
│   └── GestureDirection.swift        # Enum for swipe direction detection
├── Resources/                        # Additional resources (empty currently)
├── Assets.xcassets/                  # App icons and colors
├── Preview Content/                  # SwiftUI preview assets
└── Info.plist                        # App configuration and photo library usage descriptions
```

## Architecture

The app follows the **MVVM (Model-View-ViewModel)** architecture pattern:

1. **Model Layer**: `PhotoAsset` wraps `PHAsset` to make it compatible with SwiftUI's `@Published` mechanism
2. **View Layer**: SwiftUI views that observe ViewModel state and render the UI
3. **ViewModel Layer**: `PhotoSwipeViewModel` manages the app state, coordinates with services, and handles business logic
4. **Service Layer**: `PhotoLibraryService` encapsulates all PhotoKit interactions

## Key Components

### PhotoLibraryService
Centralized service for all photo library operations:
- Permission management (authorized, limited, denied, notDetermined)
- Fetching photo assets with configurable limits
- Deleting photos
- Moving photos to albums (creates albums if they don't exist)
- Error handling with localized Chinese messages

### PhotoSwipeViewModel
Main view model managing the photo organization flow:
- Maintains current photo index and list of all photos
- Tracks authorization status
- Implements undo functionality for delete/move operations
- Handles swipe gestures and delegates to appropriate actions
- @MainActor annotated for thread safety

### GestureDirection
Utility enum that determines swipe direction based on translation values:
- Threshold-based detection (default 80 points)
- Prioritizes the direction with larger absolute value

## Build and Run

### Requirements
- **Xcode**: 16.2 or later
- **iOS Deployment Target**: 18.2+
- **Device**: iPhone or iPad (arm64)
- **Supported Orientations**: Portrait, Landscape Left, Landscape Right

### Build Commands
```bash
# Open project in Xcode
open PhotoSwipeCleaner.xcodeproj

# Or build from command line
xcodebuild -project PhotoSwipeCleaner.xcodeproj -scheme PhotoSwipeCleaner -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Running
1. Open `PhotoSwipeCleaner.xcodeproj` in Xcode
2. Select target device/simulator
3. Press `Cmd+R` to build and run

## Development Guidelines

### Code Style
- **Comments**: Use Chinese for all documentation comments (`///`)
- **Access Control**: Explicitly mark private methods and properties
- **Thread Safety**: ViewModel uses `@MainActor` to ensure UI updates on main thread
- **Error Handling**: Use custom error types with localized descriptions

### Naming Conventions
- Classes/Structs: PascalCase (e.g., `PhotoLibraryService`)
- Methods/Variables: camelCase (e.g., `currentIndex`, `loadImage()`)
- Private properties prefixed appropriately

### SwiftUI Patterns
- Use `@StateObject` for ViewModel ownership in Views
- Use `@ObservedObject` for passed-in observable objects
- Prefer `@ViewBuilder` for conditional view composition
- Use `.sheet()` for modal presentations

## Permissions

The app requires photo library permissions. These are declared in `Info.plist`:

- `NSPhotoLibraryUsageDescription`: "需要访问您的相册来整理照片"
- `NSPhotoLibraryAddUsageDescription`: "需要访问您的相册来保存整理后的照片"

**Note**: The app supports both full access and limited access modes introduced in iOS 14+.

## Testing

Currently, the project does not include automated tests. When adding tests:

1. **Unit Tests**: Test `PhotoLibraryService` with mocked `PHPhotoLibrary`
2. **UI Tests**: Test swipe gestures and permission flows
3. **Integration Tests**: Test photo operations with sample assets

Add test targets in Xcode:
- Test target name: `PhotoSwipeCleanerTests`
- UI Test target name: `PhotoSwipeCleanerUITests`

## Security Considerations

1. **Privacy**: The app only accesses photos the user has granted permission for
2. **Data Safety**: No photos are uploaded or shared; all operations are local
3. **Undo Support**: Delete and move operations can be undone via the undo stack
4. **Error Handling**: All PhotoKit errors are caught and displayed to the user

## Bundle Information

- **Bundle Identifier**: `everthing.PhotoSwipeCleaner`
- **Version**: 1.0
- **Build**: 1

## Common Tasks for Agents

### Adding a New Gesture Action
1. Add new case to `GestureDirection` if needed
2. Handle the gesture in `PhotoSwipeViewModel.handleSwipe()`
3. Add visual feedback in `PhotoCardView.overlayView`

### Modifying Photo Operations
1. Update `PhotoLibraryService` with new PhotoKit logic
2. Add corresponding method in `PhotoSwipeViewModel`
3. Wire up UI control in `ContentView.bottomControls`

### Adding Localization
The app currently uses Chinese strings. To add English support:
1. Create `Localizable.strings` files
2. Replace hardcoded Chinese strings with `NSLocalizedString()`

## Notes for AI Agents

- All business logic should go through `PhotoLibraryService` or `PhotoSwipeViewModel`
- Keep Views stateless when possible - state belongs in ViewModel
- Use `@MainActor` for any async operations that update UI
- Test on physical device for photo library functionality (simulator has limited PhotoKit support)
- The project uses modern SwiftUI features and requires iOS 18.2+
