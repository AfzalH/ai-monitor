# AI Monitor

A native macOS menu bar app for multiple Claude, Codex through ChatGPT, and OpenCode accounts. Requires macOS 14 or later. No third-party package dependencies.

## Run

```sh
./scripts/build-app.sh
open "dist/AI Monitor.app"
```

Click **AI** in the menu bar, then **Add your first account**. The gear opens account management. You can move the app to Applications after building. Enable launch at login from its settings after moving it.

The menu bar can show several accounts, including multiple accounts from the same provider, with optional prefixes such as `x1 80% · x2 50%`. Each connected account row in Settings has its own Menu bar checkbox and prefix. Prefixes are empty by default. The first account is selected by default. Selections and prefixes stay with the account when renamed or reordered. Only selected accounts refresh in the background. Codex and OpenCode check once per minute. Claude checks no more often than every five minutes, across automatic and manual refreshes. Uncheck every account for an icon-only menu item. The compact popover shows 5-hour and weekly limits by default, with Show more for additional windows, plus reset countdowns and Codex banked resets. Settings contains the Used / Remaining switch, account renaming and ordering, and a maximum popout height control, defaulting to 40% of the screen. The popout shrinks to fit shorter lists. Usage refreshes on opening at most once per minute, including after failed attempts. Clicking Refresh bypasses the popout cooldown, but never a provider throttle. Other accounts refresh only on opening or manual refresh.

## Connect accounts

- **Claude:** default-browser authorization or a subscription OAuth access token. Browser authorization uses the Claude Code OAuth flow, with a temporary loopback callback and PKCE. The app receives the result automatically.
- **Codex:** default-browser authorization, an OAuth access token, or import a Codex `auth.json` file. Import current login respects `CODEX_HOME`, falling back to `~/.codex`. This monitors Codex usage through ChatGPT, not OpenAI API spending or ChatGPT chat-model limits.
- **OpenCode:** open the console in your default browser and paste a Go API key. An advanced console Cookie-header option lets you choose a workspace and detects Go versus prepaid Zen billing. Zen displays its balance and spending over the last 30 days, without inventing a subscription quota.

Add each subscription separately and give it a name. Claude and Codex browser sign-ins use separate authorization requests. Your default browser may already have a provider session, so select or switch to the intended account on the provider page when adding a backup. You can connect the same provider more than once.

Access tokens and cookies expire. Use **Reconnect** when prompted. Use **Rename** to change a saved account name without signing in again. This version does not refresh OAuth tokens automatically. Imported CLI credentials are snapshots; the app never modifies the original auth file or redeems its refresh token. No embedded browser is used. Claude opens your default browser and returns through a temporary localhost callback. Codex uses loopback port 1455, falling back to 1457 if occupied. Each callback requires the matching state and PKCE verifier. Sign-in times out after ten minutes and cancellation closes the listener. OpenCode has no automatic external-browser session transfer in this version.

## Local data

Credentials live in macOS Keychain under `com.local.ai-monitor.credentials`, with a different entry per account. Account names, provider names, and UUIDs live in `~/Library/Application Support/AI Monitor/accounts.json`. Usage snapshots remain in memory. Removing an account removes its Keychain entry and metadata.

Requests go directly to the selected provider. There is no backend, analytics, or credential logging. HTTP redirects are rejected for authenticated usage requests. No paid inference requests are used to measure usage. The app displays banked resets but never redeems them.

## Development

```sh
swift test
swift run AIMonitor --demo
```

Demo mode works when no real accounts have been added and never saves sample accounts. You can also enter it from the empty popover.

```sh
swift run AIMonitor --render-preview /tmp/ai-monitor-preview.png
```

The preview command renders sample data in isolation, without loading real account metadata or credentials.

`MonitorCore` contains usage parsing and network requests. `AIMonitor` contains SwiftUI views, account storage, Keychain access, and default-browser authorization. Tests use synthetic provider responses and an in-memory credential vault.

## Status and limits

The app builds locally and has automated parser, request-scope, persistence, and cancellation checks. Live provider sign-in and quota responses still need verification with your accounts. The default-browser handoff, callback rejection, cancellation, and token exchange are tested locally using synthetic credentials. The native UI automation service was unavailable during development, so menu interaction has not been automated.

Provider usage routes are mostly undocumented and can change. An unsupported response shows an error instead of zero usage. Failed refreshes preserve the previous snapshot and mark it stale. Optional Codex reset-credit failures do not hide working quota data. Missing reset times stay unknown.

The build script produces a universal Apple Silicon and Intel app, then signs it with a Developer ID Application certificate, hardened runtime, and a secure timestamp. It uses the same signing approach as `~/voice`, without that app's microphone or Apple Events entitlements. Set `CODESIGN_IDENTITY` to select a certificate, or `CODESIGN_IDENTITY=-` for an explicit local ad-hoc build. Set `AI_MONITOR_ARCHS=arm64` to build only for Apple Silicon.

To notarize the signed app and produce a distributable ZIP:

```sh
./scripts/notarize.sh
```

This uses the existing `vBoard-Notary` Keychain profile. Override it with `NOTARY_PROFILE` if needed. Credentials remain in Keychain. The script submits the ZIP to Apple, waits for acceptance, staples the ticket to the app, verifies Gatekeeper acceptance, and rebuilds the ZIP with the ticket included. Outputs are `dist/AI-Monitor-<version>.zip` and its SHA-256 checksum.

The submission ID is saved in `dist/notarization-submission.json`. If waiting times out, run `./scripts/notarize.sh SUBMISSION_ID` to resume without submitting again. Do not rebuild or modify the app between submission and stapling. A rebuild needs a new notarization submission.

Protocol research used the public [CodexBar provider documentation](https://github.com/steipete/CodexBar/tree/main/docs) and corresponding fetchers, with an independent implementation here. See [provider notes](docs/providers.md).

### Claude request throttling

We could not find an official request budget for the subscription OAuth usage endpoint. The five-minute interval is this app's conservative policy, not a guaranteed provider limit. A 429 pauses Claude checks for at least 15 minutes, then 30 and 60 minutes on repeated throttling. A longer `Retry-After` value always wins. The pause is saved across restarts, keyed by the account ID and a digest of the credential plus usage URL. Reconnecting an existing account keeps its cooldown, and existing usage stays visible. Other apps and Claude Code sessions can still consume the same account's request budget.

References: [Anthropic rate-limit guidance](https://platform.claude.com/docs/en/api/rate-limits) and a [firsthand usage-endpoint throttling report](https://github.com/anthropics/claude-code/issues/77477). The published inference API rate tables are not a documented limit for the subscription usage endpoint.
