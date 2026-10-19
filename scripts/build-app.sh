#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -a architectures <<< "${AI_MONITOR_ARCHS:-arm64 x86_64}"
export MACOSX_DEPLOYMENT_TARGET=14.0
binaries=()
for arch in "${architectures[@]}"; do
  swift build -c release --arch "$arch"
  binary_dir="$(swift build -c release --arch "$arch" --show-bin-path)"
  binaries+=("$binary_dir/AIMonitor")
done
app_path="$PWD/dist/AI Monitor.app"
mkdir -p "$app_path/Contents/MacOS"
if [[ ${#binaries[@]} -eq 1 ]]; then
  cp "${binaries[0]}" "$app_path/Contents/MacOS/AIMonitor"
else
  lipo -create "${binaries[@]}" -output "$app_path/Contents/MacOS/AIMonitor"
fi
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AIMonitor</string>
<key>CFBundleIdentifier</key><string>com.local.ai-monitor</string>
<key>CFBundleName</key><string>QuotaBar for AI</string>
<key>CFBundleDisplayName</key><string>QuotaBar for AI</string>
<key>CFBundleVersion</key><string>16</string>
<key>CFBundleShortVersionString</key><string>0.1.15</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)"
fi
if [[ -z "$identity" ]]; then
  echo "No Developer ID identity found. Set CODESIGN_IDENTITY=- for a local ad-hoc build." >&2
  exit 1
fi
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app_path"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app_path"
fi
codesign --verify --deep --strict "$app_path"
lipo -info "$app_path/Contents/MacOS/AIMonitor"
printf 'Built %s\n' "$app_path"
