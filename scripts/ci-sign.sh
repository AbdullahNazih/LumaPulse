#!/bin/zsh
set -euo pipefail
set +x
cd "$(dirname "$0")/.."
[[ -z "$(/usr/libexec/PlistBuddy -c 'Print :LumaPulseReleaseSuffix' Resources/Info.plist)" ]] || { echo 'Remove the release-candidate suffix before a signed stable release.' >&2; exit 1; }
for name in APPLE_CERTIFICATE_P12_BASE64 APPLE_CERTIFICATE_PASSWORD APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID LUMAPULSE_SIGNING_IDENTITY; do
  [[ -n "${(P)name:-}" ]] || { echo "Missing signing configuration: $name" >&2; exit 1; }
done
release_temp=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lumapulse-sign.XXXXXX")
keychain="$release_temp/release.keychain-db"
cleanup() { security delete-keychain "$keychain" >/dev/null 2>&1 || true; rm -rf "$release_temp"; }
trap cleanup EXIT
umask 077
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | /usr/bin/base64 --decode > "$release_temp/certificate.p12"
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$release_temp/certificate.p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
export LUMAPULSE_KEYCHAIN="$keychain"
export LUMAPULSE_BUILD_MODE=distribution
export LUMAPULSE_UNIVERSAL=1
zsh scripts/build.sh
ditto -c -k --keepParent dist/LumaPulse.app "$release_temp/notary.zip"
xcrun notarytool submit "$release_temp/notary.zip" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait --timeout 30m
xcrun stapler staple dist/LumaPulse.app
zsh scripts/package.sh
