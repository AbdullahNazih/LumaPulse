# Maintaining and releasing LumaPulse

## Versioning

Keep the permanent bundle identifier `com.anazih.lumapulse`. Set the three-part version and increasing numeric build number in Resources/Info.plist. For candidates, use LumaPulseReleaseSuffix `-rc.N`; for stable releases set it to an empty string. The release tag is derived from those values. Never replace an existing version's assets or move published tags; issue a new patch version instead.

Run `zsh scripts/test.sh` and `zsh scripts/build.sh`, inspect the interface, and update CHANGELOG.md before publishing. Source changes should go through a pull request with Security and build passing. Review Dependabot updates and keep Action references pinned to full commit SHAs.

## GitHub release workflow

Run Publish release from main with mode preview or signed. Tests run before signing material is loaded. Preview packages are explicitly marked as prereleases and never become the stable latest release. The app's updater ignores prereleases. Signed mode refuses release-candidate versions and requires Developer ID signing, notarization, stapling, and Gatekeeper validation. Packaging creates a universal app ZIP and its SHA-256 checksum; the publication job verifies checksums before uploading assets and creating the immutable version tag.

Configure the GitHub environment named release with:

| Setting | Type |
| --- | --- |
| APPLE_CERTIFICATE_P12_BASE64 | Secret |
| APPLE_CERTIFICATE_PASSWORD | Secret |
| APPLE_ID | Secret |
| APPLE_APP_SPECIFIC_PASSWORD | Secret |
| APPLE_TEAM_ID | Variable |
| LUMAPULSE_SIGNING_IDENTITY | Variable, Developer ID Application identity |

Use environment approval rules and protect main with required CI. The signing job creates a temporary keychain and removes its certificate material on exit. Never upload certificates, provider API keys, or authenticated diagnostics to issues or artifacts.

## Update notification behavior

The app reads the public `/releases/latest` endpoint for AbdullahNazih/LumaPulse using bounded HTTPS requests. It validates stable semantic versions and the exact repository release URL, then notifies once per new version. It does not download or execute binaries. A signed stable release with a higher semantic version automatically becomes eligible for notifications without an app-code change.

## Download reports

`python3 scripts/download-report.py` reads every releases page and stores a private local baseline under .reports, which is gitignored. Reports count app ZIP/DMG/PKG downloads only and track asset IDs, replacements, missing assets and reset counters. The daily Codex automation is scheduled at 07:00 Asia/Kuwait. It reports in the original chat and depends on that computer and the app being available to run scheduled work; sleep can delay delivery.
