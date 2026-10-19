# App Store listing

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

App Store record: 6824478425. The old rejected record, 6824230786, uses com.afzalh.aimonitor and is named QuotaBar for AI Legacy.

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

## Review notes background

Include the loopback-listener explanation and reviewer steps from [the rejection response](rejection-2026-10-19.md).

This is a menu-bar-only utility. Click its gauge icon after launch. Settings contains account setup and Quit.

The empty state offers sample data for viewing the interface without credentials. Live verification requires a supported provider account. The submitted review notes describe both sample mode and live account setup. Apple has not yet accepted this review access.

OAuth compatibility integrations use the public Claude Code and Codex client identifiers with PKCE and temporary loopback callbacks. Usage routes are mostly undocumented. Claude sign-in currently requests user:profile and user:inference. Codex requests openid, profile, email, and offline_access, but the app only retains the access token and reconnects when it expires. No inference calls, purchases, or banked-reset redemption are performed. These scopes have not yet been reduced and validated. The owner chose to submit with the existing integrations. Provider permission requests were not sent; Apple has not yet reviewed this replacement submission.

## Submission status

Version 1.0.0, build 20 was submitted on October 19, 2026 and is waiting for review. Contact details were entered privately in App Store Connect. Privacy and age-rating answers are saved, and the owner completed the content-rights declaration. See [submission details](submission.md) for the recorded state.
