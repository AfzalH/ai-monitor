#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/load-env.sh
[[ -n "${ANTIGRAVITY_CLIENT_SECRET:-}" ]] || echo "ANTIGRAVITY_CLIENT_SECRET is not set; building without Antigravity." >&2
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before generating the App Store project.' >&2; exit 1; }
xcodegen generate --spec AppStore/project.yml
xcodebuild -project AppStore/AIMonitorAppStore.xcodeproj -scheme AIMonitor \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$PWD/dist/AI-Monitor-AppStore.xcarchive" \
  ANTIGRAVITY_CLIENT_SECRET="${ANTIGRAVITY_CLIENT_SECRET:-}" archive "$@"
