# Security policy

Report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/AbdullahNazih/LumaPulse/security/advisories/new). Do not include API keys or authenticated URLs in public issues. If private reporting is unavailable, open an issue requesting a private contact without disclosing the vulnerability.

## Protections

- macOS App Sandbox with outbound network-client access only; no file, camera, microphone, location, network-server, or automation entitlements.
- Hardened runtime; no debugging, unsigned-library, or executable-memory exceptions.
- API credentials in macOS Keychain. They are never placed in UserDefaults, source files, update requests, or diagnostic logs.
- TLS 1.2 or newer with system certificate validation. Cross-host HTTP redirects are rejected.
- RSS responses are capped at 1 MiB, WebSocket messages at 256 KiB, article text is bounded, and XML DTD/entity declarations are rejected.
- Article links are HTTPS and constrained to their publisher domains. Content is rendered as text, never executable HTML.
- Updates only check this project's GitHub repository over HTTPS. Version and release-URL validation reject unrelated repositories and prereleases. The app never installs or executes downloaded updates.

## Release assurance

CI runs functional and adversarial-input checks, source-secret checks, workflow-pin checks, script validation, and packaged-code-signature/entitlement inspections. Actions are pinned to immutable commits, PR jobs have read-only repository permission, and release publication is separated into a job with write permission. Only manual release runs from main can publish; signing secrets are confined to the release environment. Dependabot proposes Action updates weekly.

Preview builds are ad-hoc signed and **not notarized**. Signed stable releases require a Developer ID certificate, a secure timestamp, successful notarization, a stapled ticket, and Gatekeeper assessment. The release workflow fails closed when those requirements are missing. SHA-256 files detect download corruption; they are not a substitute for Developer ID signing.

There has been no independent security audit or penetration test. Provider authentication, account entitlements, service reconnect behavior and Keychain access require validation with real accounts. No software is guaranteed free of vulnerabilities. The latest stable release is the supported version once one exists; until then the newest release candidate is maintained on a best-effort basis.
