#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before generating the App Store project.' >&2; exit 1; }
xcodegen generate --spec AppStore/project.yml
xcodebuild -project AppStore/AIMonitorAppStore.xcodeproj -scheme AIMonitor \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$PWD/dist/AI-Monitor-AppStore.xcarchive" archive "$@"
