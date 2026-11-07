#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/LumaPulse.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
suffix=$(/usr/libexec/PlistBuddy -c 'Print :LumaPulseReleaseSuffix' "$app/Contents/Info.plist")
tag="v${version}${suffix}"
[[ "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$' ]] || { echo 'Invalid version.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/LumaPulse" -verify_arch arm64 x86_64
archive="LumaPulse-${tag}-macOS-universal.zip"
if [[ "${LUMAPULSE_BUILD_MODE:-local}" == distribution ]]; then
  [[ -z "$suffix" ]] || { echo 'Stable signing requires an empty release suffix.' >&2; exit 1; }
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
else
  [[ -n "$suffix" ]] || { echo 'Preview releases require a release-candidate suffix.' >&2; exit 1; }
  archive="LumaPulse-${tag}-macOS-universal-preview.zip"
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
echo "Packaged: dist/$archive"
