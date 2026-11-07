#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
swift build -c release --disable-sandbox --cache-path .build/cache
build_mode="${LUMAPULSE_BUILD_MODE:-local}"
case "$build_mode" in
  local) ;;
  distribution) [[ "${LUMAPULSE_SIGNING_IDENTITY:-}" == 'Developer ID Application: '* ]] || { echo 'Developer ID Application identity required.' >&2; exit 1; } ;;
  *) echo 'Invalid build mode.' >&2; exit 1 ;;
esac
binary="$PWD/.build/release/LumaPulse"
if [[ "${LUMAPULSE_UNIVERSAL:-0}" == 1 ]]; then
  binaries=()
  for architecture in arm64 x86_64; do
    swift build -c release --arch "$architecture" --disable-sandbox --cache-path .build/cache
    binary_directory=$(swift build -c release --arch "$architecture" --show-bin-path --disable-sandbox --cache-path .build/cache)
    binaries+=("$binary_directory/LumaPulse")
  done
  lipo -create "${binaries[@]}" -output .build/LumaPulse-universal
  binary="$PWD/.build/LumaPulse-universal"
fi
app="$PWD/dist/LumaPulse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/LumaPulse.next"
mv -f "$app/Contents/MacOS/LumaPulse.next" "$app/Contents/MacOS/LumaPulse"
cp Resources/Info.plist "$app/Contents/Info.plist"
for notice in LICENSE.txt PRIVACY.md; do cp "$notice" "$app/Contents/Resources/$notice"; done
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
if [[ "$build_mode" == distribution ]]; then
  sign_options=()
  if [[ -n "${LUMAPULSE_KEYCHAIN:-}" ]]; then sign_options+=(--keychain "$LUMAPULSE_KEYCHAIN"); fi
  codesign --force --options runtime --entitlements Resources/LumaPulse.entitlements --sign "$LUMAPULSE_SIGNING_IDENTITY" --timestamp "${sign_options[@]}" "$app"
else
  codesign --force --options runtime --entitlements Resources/LumaPulse.entitlements --sign - --timestamp=none "$app"
fi
codesign --verify --deep --strict "$app"
python3 scripts/security-check.py --app "$app" --mode "$build_mode"
echo "Built: $app"
