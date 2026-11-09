# Changelog

## 1.0.0-rc.2

### Added

- Uninstall LumaPulse from Preferences. After confirmation and macOS folder approval, LumaPulse moves the running app to the Trash, clears local settings and bookmarks, removes its saved provider credentials, and quits. Emptying the Trash removes the bundle from disk.

### Changed

- The menu bar stays static while idle. Alert pulses respect Low Power Mode and Reduce Motion.
- RSS polling runs only when live headlines and at least one RSS source are enabled. Polling slows from one minute to five minutes in Low Power Mode.
- Automatic update checks stop scheduling background work when turned off.

### Security

- The uninstall flow validates the selected folder and targets only the running app bundle and LumaPulse's own settings and Keychain entries. Folder access comes from the macOS picker and is limited to the uninstall operation.

## 1.0.0-rc.1 — 8 November 2026

- Native macOS menu bar briefing for stocks, crypto, gold, silver and macro news.
- Optional Benzinga and Trading Economics streaming clients with Keychain-backed credentials.
- Selectable CNBC, CoinDesk, FXStreet, Federal Reserve and BBC RSS fallback.
- Automatic soft rose alerts, saved display durations, search, asset filters and bookmarks.
- Automatic GitHub update notifications with strict repository/version validation.
- App Sandbox, hardened runtime, bounded network responses, restricted article links and protected XML parsing.
- Pinned CI and release workflows, source-secret gates, universal packaging and a notarization-ready signing path.
- Aggregate release-download reporting with asset-ID baselines.

This is a release candidate. Developer ID signing/notarization and authenticated streaming verification remain outstanding.
