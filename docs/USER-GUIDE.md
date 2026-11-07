# LumaPulse user guide

## Install

Download the ZIP from [GitHub Releases](https://github.com/AbdullahNazih/LumaPulse/releases), extract it, and move LumaPulse.app to Applications. Requires macOS 13 or newer; release packages support Apple Silicon and Intel.

The current release candidate uses an ad-hoc signature and is not notarized. Gatekeeper may block an internet-downloaded preview. Prefer building from the reviewed source or waiting for a notarized stable release. LumaPulse does not disable Gatekeeper or change macOS security settings.

## Your briefing

Click LumaPulse in the menu bar. Open the sliders control to enable live headlines. Select Stocks, Crypto, Gold, Silver, Macro or World to filter the reading panel. Search headlines and descriptions, bookmark stories, and click a headline to visit its original publisher. Market-driver labels identify topics such as rates, inflation and company results; they do not predict price direction.

CNBC, CoinDesk, FXStreet and Federal Reserve RSS are selected initially. BBC World is optional. RSS refreshes once per minute and may be delayed by its publishers. If a source fails, other sources keep working and the failed source's previously loaded stories remain with an unavailable status.

## Streaming providers

Under Recommended live providers, enter a Benzinga streaming token and/or Trading Economics key:secret, then choose Save & connect. Each service requires an appropriate account and streaming entitlement. Credentials stay in macOS Keychain. Reconnect uses the saved key; Disconnect stops that provider's automatic reconnection. Turning live mode off pauses both streams. Account credentials and connectivity still need validation for this release candidate.

## Alerts

Fresh market-driver news and high-importance economic releases can display a soft rose menu bar alert and banner automatically. Choose 5, 10, 30 seconds or a custom duration from 1 second to 30 minutes in Preferences. The setting is saved. The newest qualifying alert replaces the current alert; the close control dismisses it early. Turn Automatic market alerts off to keep the briefing without pop-up alerts.

Test alert shows an explicitly fictional demo. DEMO content is never presented as live reporting. Live notifications are labeled Market alert or Economic release.

## Updates and privacy

Update checks run at launch and every six hours while the app is running. Preferences includes Check for updates and an on/off switch for automatic checks. New stable versions produce a notification linking to this repository's release page. Download and replace the app yourself; nothing is silently installed. Existing preferences are retained by the stable app identifier across future releases.

There is no analytics backend. Read the [privacy notice](../PRIVACY.md). GitHub download counts are aggregate downloads, not unique users. To quit, use Quit at the bottom of the panel. To uninstall, quit and remove the app; API keys can be revoked with the provider or removed using Keychain Access by searching for com.anazih.lumapulse.providers.
