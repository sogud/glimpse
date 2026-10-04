#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_directory=$(mktemp -d -t glimpse-checks)
trap 'rm -rf -- "$check_directory"' EXIT
swift run GlimpsePhotosCLIChecks
python3 Tests/CLITransportChecks.py
swift build --product glimpse
python3 Tests/CLICommandChecks.py
swiftc Sources/PhotosCLIKit/CommandRunner.swift Tests/CommandRunnerChecks.swift -o "$check_directory/command"
"$check_directory/command"
swiftc Sources/SmartCore/LocalPhotoClassificationCore.swift Sources/SmartCore/LocalPhotoClassificationTask.swift \
    Tests/NativeTaskStateChecks.swift -o "$check_directory/native"
"$check_directory/native"
swiftc Sources/SmartCore/LocalPhotoClassificationCore.swift Sources/SmartCore/LocalPhotoClassificationTask.swift \
    Tests/NativeGUIWorkflowChecks.swift -o "$check_directory/native-gui"
"$check_directory/native-gui"
swiftc -frontend -parse MacApp/PhotoClassificationCoordinator.swift MacApp/PhotoClassificationViews.swift MacApp/MacPhotoLibraryService.swift
git diff --check
