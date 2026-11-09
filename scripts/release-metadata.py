import os
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
tag = 'v' + info['CFBundleShortVersionString'] + info['LumaPulseReleaseSuffix']
assert re.fullmatch(r'v\d+\.\d+\.\d+(-rc\.\d+)?', tag)
mode = os.environ.get('RELEASE_MODE', 'preview')
assert mode in {'preview', 'signed'}
if mode == 'signed':
    assert '-rc.' not in tag
status = ('**Preview build: ad-hoc signed, not Developer ID signed or notarized.** This is a release candidate for testing; Gatekeeper may block internet-downloaded builds. A notarized stable release is pending Developer ID credentials.' if mode == 'preview' else '**Developer ID signed and notarized for macOS.**')
changelog = (root / 'CHANGELOG.md').read_text()
heading = re.escape(tag[1:])
change = re.search(rf'^## {heading}(?:[ \t]+—[^\n]*)?\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
assert change, f'Missing changelog entry for {tag}'
notes = f'''{status}

## What’s changed

{change.group(1).strip()}

## About LumaPulse

Your markets, at a glance. LumaPulse brings stocks, crypto, gold, silver and macro headlines to the macOS menu bar.

- Optional Benzinga and Trading Economics streams, with credentials stored in macOS Keychain.
- CNBC, CoinDesk, FXStreet and Federal Reserve RSS fallback.
- Soft rose alerts with 5-, 10-, 30-second or custom durations up to 30 minutes.
- Search, asset filters, bookmarks and automatic update notifications.
- App Sandbox, outbound networking, hardened runtime and bounded input parsing.

Requires macOS 13 or later. The ZIP includes Apple Silicon and Intel support. Extract the app and move it to Applications. Check its SHA-256 using the accompanying checksum file.

**Known limits:** authenticated streaming and Keychain access still require account-level validation. API subscriptions are separate. Market-driver alerts use topic rules and do not predict price direction. Update checks notify; they never install code automatically.

See the [user guide](https://github.com/AbdullahNazih/LumaPulse/blob/main/docs/USER-GUIDE.md), [privacy notice](https://github.com/AbdullahNazih/LumaPulse/blob/main/PRIVACY.md), and [security policy](https://github.com/AbdullahNazih/LumaPulse/security/policy).
'''
(root / 'dist/release-notes.md').write_text(notes)
(root / 'dist/release-tag.txt').write_text(tag + '\n')
