# Provider connections

Checked on 2026-10-18 against the public CodexBar provider documentation and implementation. These routes are compatibility integrations, not a promise of stable public APIs.

Claude browser sessions use `GET https://claude.ai/api/organizations`, then `/api/organizations/{uuid}/usage`. OAuth tokens use `GET https://api.anthropic.com/api/oauth/usage` with the `anthropic-beta: oauth-2025-04-20` header. The parser supports five-hour, weekly, model-specific weekly, and newer scoped `limits` entries. Percentages are provider-reported utilization, not token-count estimates.

Codex uses `GET https://chatgpt.com/backend-api/wham/usage`. The same credential and optional `ChatGPT-Account-Id` scope are used for `/wham/rate-limit-reset-credits`. Window labels come from `limit_window_seconds`, so a weekly-only plan is not mislabeled as five-hour usage. Extra model-specific limits are shown separately. The reset endpoint is read-only.

OpenCode Go API keys use `GET https://opencode.ai/zen/go/v1/usage`. Its `usage.rolling`, `weekly`, and `monthly` percentages are already percentages. A value of `0.5` means 0.5%, not 50%.

OpenCode browser sessions use `/console/api/orgs` for workspace selection, then `/console/api/go/status` with `x-org-id`. Meters divide `usedMicroCents` by `limitMicroCents`; the monthly reset falls back to `access.endsAt` if absent. A successful null Go response is not sufficient to infer Zen billing. The app also requires `/console/api/orgs/current` to confirm `hasGoSubscription: false` and `/console/api/billing/status` to confirm `mode: pay-as-you-go`. It then reads `/console/api/usage/summary?range=30d`. Micro-cent currency amounts are divided by 100,000,000 to get USD. Legacy OpenCode dashboards and other billing modes are not supported in this version.

References:

- [Claude integration](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)
- [Codex OAuth integration](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md)
- [OpenCode integration](https://github.com/steipete/CodexBar/blob/main/docs/opencode.md)
- [OpenAI banked resets](https://help.openai.com/en/articles/20001498-how-banked-codex-resets-work)

## Default-browser authorization

Version 0.1.1 removes the embedded WebKit login. Claude opens `https://claude.com/cai/oauth/authorize`, matching the installed Claude Code authorization configuration, with the public Claude Code client identifier, a PKCE challenge, a random state, and an ephemeral `http://localhost:{port}/callback` redirect. The token exchange posts JSON to `https://platform.claude.com/v1/oauth/token`. It requests `user:profile user:inference` scopes for subscription access; the app makes no inference calls. Renewal posts JSON with `grant_type: refresh_token`, the refresh token, the client identifier and the same scopes to the same token endpoint, matching Claude Code. The provider's consent page may identify the OAuth client as Claude Code.

Codex opens `https://auth.openai.com/oauth/authorize` using the public Codex client identifier and a loopback `/auth/callback` redirect on registered port 1455 or 1457. The token exchange posts form data to `https://auth.openai.com/oauth/token`. Renewal posts JSON with `grant_type: refresh_token` and scope `openid profile email`, matching the Codex CLI.

For both browser flows the app keeps the access token, refresh token, expiry and account scope in its own Keychain entry. It renews within a minute of expiry, or once after a usage request is rejected with HTTP 401, then retries. A rotated refresh token replaces the stored one; if the response omits it, the previous one is kept. A rejected renewal (HTTP 400 or 401) asks the user to reconnect. Providers rotate refresh tokens, so the app never redeems a refresh token from an imported CLI file. Neither flow modifies CLI credentials.

The callback listener binds to `127.0.0.1`, checks the request path, host and state, rejects duplicate callback parameters, and never includes codes in its browser response. Cancelling sign-in invalidates pending completion and closes the listener. OpenCode uses an API key by default, with manual console cookies retained as an advanced option for Zen billing.

Authorization configuration references include the installed official Claude Code binary and [the official Codex login server](https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs). These are compatibility flows using provider CLI client identifiers, not independently registered OAuth applications.
