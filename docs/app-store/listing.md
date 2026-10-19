# App Store listing draft

Name: QuotaBar for AI
Subtitle: AI subscription quota tracker
Primary category: Utilities
Secondary category: Productivity
Primary language: English (U.S.)
Price: Free
Target App Store bundle ID: com.srizon.quotabar
Version: 1.0.0, build 20
Support URL: https://github.com/AfzalH/ai-monitor/issues
Marketing URL: https://github.com/AfzalH/ai-monitor
Privacy policy URL: https://www.srizon.com/privacy
Keywords: quota,usage,AI,subscription,monitor,menu bar,limits,reset,productivity

The rejected record uses com.afzalh.aimonitor. A new App Store record is required for the new bundle ID.

## Promotional text

Keep track of your AI subscription limits from the menu bar. Connect multiple accounts, see reset countdowns, and choose which quotas stay visible.

## Description

QuotaBar for AI puts your AI subscription usage in the macOS menu bar.

Connect Claude subscriptions, Codex through ChatGPT subscriptions, and OpenCode Go accounts. Add more than one account from the same provider and give each connection its own name.

See five-hour, weekly, and monthly limits when your provider reports them, along with reset countdowns and available Codex banked resets. Expand an account to see additional limits.

Choose individual accounts to display in the menu bar, with optional prefixes to tell them apart. Reorder accounts, switch between used and remaining percentages, adjust the popout height, and enable launch at login.

Credentials stay in macOS Keychain. Requests go directly to the provider. QuotaBar for AI has no advertising, tracking, or developer-operated backend.

An existing provider account is required for live usage. QuotaBar for AI does not include or sell AI subscriptions. Codex monitoring covers Codex usage through ChatGPT, not ChatGPT chat-model limits or OpenAI API billing. Provider limits and access can change. Reconnect an account when its sign-in expires.

QuotaBar for AI is an independent utility and is not affiliated with or endorsed by the supported providers.

## Review notes draft

This is a menu-bar-only utility. Click its gauge icon after launch. Settings contains account setup and Quit.

The empty state offers sample data for viewing the interface without credentials. Live verification requires a supported provider account. Confirm Apple's requirements for review access before submission; do not assume sample mode alone is sufficient.

OAuth compatibility integrations use the public Claude Code and Codex client identifiers with PKCE and temporary loopback callbacks. Usage routes are mostly undocumented. Claude sign-in currently requests user:profile and user:inference. Codex requests openid, profile, email, and offline_access, but the app only retains the access token and reconnects when it expires. No inference calls, purchases, or banked-reset redemption are performed. These scopes have not yet been reduced and validated. Third-party authorization under guideline 5.2.2 remains to be confirmed before submission.

## Owner input still needed

- Confirm legal seller identity and public availability territories.
- Supply App Review contact details through App Store Connect, not public repository files.
- Confirm provider authorization and any required documentation.
- Complete Apple's age-rating, content-rights, export-compliance, and trader-status declarations accurately.
- Provide review access acceptable to Apple.
