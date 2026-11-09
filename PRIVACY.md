# Privacy

LumaPulse has no analytics SDK, advertising, account service, or developer-operated backend.
API credentials are stored in macOS Keychain when you select Save & connect.
Disconnect stops reconnection but retains the key; provider access can be revoked in the provider account.
Preferences and bookmark IDs stay in the app's macOS sandbox. Article content is held in memory. The uninstall action clears these preferences and removes the saved provider credentials for your macOS account.

Enabled RSS sources receive ordinary HTTPS requests from your device, including its IP address.
Benzinga and Trading Economics receive the credentials needed to authenticate their streams.
The app does not log keys or authenticated URLs. Provider privacy policies and subscriptions apply.
Opening an article sends an ordinary browser visit to the publisher.

Automatic update checks contact the public GitHub releases API at launch and every six hours.
No provider keys are sent to GitHub. Turn these checks off in Preferences.
The updater only notifies; it does not download, execute, or install software.
GitHub receives ordinary connection metadata. There is no per-device download tracking by LumaPulse.
Maintainer download reports use aggregate GitHub release-asset counts, not identifiable users.
