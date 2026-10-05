#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_directory="$(mktemp -d -t glimpse-appkit-checks)"
trap 'rm -r "$check_directory"' EXIT
swiftc Sources/SmartCore/LocalPhotoClassificationCore.swift Sources/SmartCore/LocalPhotoClassificationTask.swift \
    MacApp/NativeControls.swift MacApp/PhotoInspectorWindowController.swift MacApp/PhotoReviewViewController.swift \
    Tests/AppKitReviewChecks.swift -o "$check_directory/review"
"$check_directory/review" "$@"
swiftc Sources/SmartCore/LocalPhotoClassificationCore.swift Sources/SmartCore/LocalPhotoClassificationTask.swift \
    MacApp/LMStudioClient.swift MacApp/NativeControls.swift MacApp/NewTaskViewController.swift \
    Tests/AppKitCreationChecks.swift -o "$check_directory/create"
"$check_directory/create"
