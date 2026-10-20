#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
profile="${NOTARY_PROFILE:-vBoard-Notary}"
app_path="$PWD/dist/QuotaBar for AI.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
archive="$PWD/dist/QuotaBar-for-AI-$version.zip"
submission="$PWD/dist/notarization-submission.json"
status_file="$PWD/dist/notarization-status.json"

codesign --verify --deep --strict "$app_path"
signature="$(codesign -dvv "$app_path" 2>&1)"
if [[ "$signature" != *"Authority=Developer ID Application:"* || "$signature" != *"runtime"* ]]; then
  echo "Build with a Developer ID Application identity and hardened runtime first." >&2
  exit 1
fi

# Pass a saved submission ID to resume without uploading another copy.
if [[ $# -gt 0 ]]; then
  submission_id="$1"
else
  ditto -c -k --keepParent "$app_path" "$archive"
  xcrun notarytool submit "$archive" --keychain-profile "$profile" --output-format json > "$submission"
  submission_id="$(plutil -extract id raw -o - "$submission")"
fi
printf 'Notarization submission: %s\n' "$submission_id"
xcrun notarytool wait "$submission_id" --keychain-profile "$profile" --timeout 10m --output-format json > "$status_file"
status="$(plutil -extract status raw -o - "$status_file")"
if [[ "$status" != "Accepted" ]]; then
  xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$PWD/dist/notarization-log.json"
  printf 'Notarization status: %s. See dist/notarization-log.json\n' "$status" >&2
  exit 1
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
# Recreate the distributable so it includes the stapled ticket for offline checks.
ditto -c -k --keepParent "$app_path" "$archive"
(cd dist && shasum -a 256 "$(basename "$archive")" > "QuotaBar-for-AI-$version.sha256")
printf 'Signed, notarized, and stapled: %s\n' "$app_path"
printf 'Distribution archive: %s\n' "$archive"
