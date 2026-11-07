# Recommended provider setup

LumaPulse 0.3 includes streaming clients for Benzinga news and Trading Economics economic releases. The clients are implemented from the public schemas; authenticated end-to-end testing remains pending valid credentials with streaming entitlement. The app does not create accounts or purchase plans.

Open Preferences, find **Recommended live providers**, and enter each account's credentials into its secure field. Use **Save & connect**. Provider status is displayed beside the controls. Benzinga requires a streaming token; Trading Economics expects the account's API `key:secret` credential. Keys are stored in macOS Keychain, never in the repository or UserDefaults. The app does not log authenticated URLs, raw errors containing credentials, or key values. Transport uses TLS and an ephemeral URL session.

Connections send protocol heartbeats every 30 seconds and retry temporary failures with exponential backoff up to 60 seconds. A disconnected provider does not prevent RSS or the other provider from working. Authentication or entitlement failures require correcting the credentials/account access. No historical backfill is requested; the briefing builds as live events arrive. Supported streams depend on the account's plan.

Benzinga messages use stable article IDs for updates and deletions. Alerts require newly created, fresh news matching market-driver terms or an explicit breaking headline. Forecast/analysis headlines do not trigger alerts. Economic-release alerts require an actual value, importance 3, and a release timestamp within five minutes. Values show reported units and actual/forecast/previous comparisons. These rules identify alert candidates, not expected price direction. The soft rose design is shared by the menu bar and banner.

Public API references:

- [Benzinga news-stream schema and endpoint](https://docs.benzinga.com/ws-reference/data-websocket/get-news-stream)
- [Trading Economics calendar streaming](https://docs.tradingeconomics.com/economic_calendar/streaming/)
- [Trading Economics authentication](https://docs.tradingeconomics.com/get_started/authentication/)
