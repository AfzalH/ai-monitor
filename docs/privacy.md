# Privacy policy

Effective date: October 20, 2026

AI Monitor, listed on the Mac App Store as QuotaBar for AI, is a macOS utility that displays usage information for subscriptions you connect. It is developed by Md Afzal Hossain.

## Data on your Mac

AI Monitor stores connected-account names, provider identifiers, and app preferences locally. Access tokens, refresh tokens from browser sign-in, API keys, and session cookies are stored in macOS Keychain. Refresh tokens are sent only to the provider that issued them, to renew access. The latest usage figures for each account, such as plan name, percentages, and reset times, are cached in a local file so they appear after a relaunch. Removing an account deletes its cached figures. Local request-cooldown records contain account identifiers and cryptographic digests, not the original credentials.

The app does not send your account credentials or usage information to the developer. It has no developer-operated backend, advertising, analytics SDK, or tracking system.

## Connections to providers

When you connect or refresh an account, AI Monitor sends authentication information directly to the selected provider and retrieves usage information. The provider receives network information, such as your IP address, as part of that connection. Provider websites opened for sign-in or account management are subject to their own privacy policies.

The app accesses an authentication file only when you choose to import it. It does not modify that file. It does not read your conversations, prompts, or generated responses.

## Removing data

Remove an account in Settings to delete its saved connection metadata and Keychain credential. Previously created local preference and cooldown records may remain. Removing an account does not cancel the provider subscription. Uninstalling the app does not necessarily remove macOS Keychain entries or all local settings.

## Contact

For privacy questions, use the [project issue tracker](https://github.com/AfzalH/ai-monitor/issues). Issues are public. Do not include credentials, private account information, or conversation content.
