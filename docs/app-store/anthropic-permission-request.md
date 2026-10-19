# Claude integration permission request

Historical draft for Anthropic Product Support. Not sent. The owner chose to proceed with App Review using the existing integration.

Subject: Approved authentication for a read-only Claude subscription quota monitor

I maintain QuotaBar for AI, a free, open-source macOS menu bar app, and am preparing a Mac App Store release. Source: https://github.com/AfzalH/ai-monitor

The app displays a user's subscription usage percentages and reset times. It does not send prompts, run inference, read conversations, or route model traffic through a server. Credentials stay in the user's macOS Keychain; requests go directly from their Mac to the provider.

The current Claude integration uses the Claude Code OAuth client ID with PKCE and requests `user:profile user:inference`. It reads `https://api.anthropic.com/api/oauth/usage`. There is also a manual session-cookie option that reads the user's organizations and their organization usage endpoint. I have not established permission to distribute these authentication methods and would like guidance on an approved integration.

Could you confirm whether this read-only quota-monitoring integration is permitted for distribution, including on the Mac App Store? If the current methods are not approved, is there a supported read-only endpoint and a way to register a dedicated OAuth client? We would prefer the narrowest available scope and do not need inference permission.

Please also confirm the supported polling limits and whether usage metadata may be displayed in the app and its screenshots. The app already caches results, throttles Claude requests, and backs off on rate-limit responses.

Please route this request to the team responsible for third-party authentication and integration permissions. Written confirmation or instructions for an approved integration would let us complete Apple's third-party service authorization requirements accurately.

## Support route

Use Claude's account menu, Get help, then Send us a message. Ask for Product Support escalation if needed. Anthropic documents this route at https://privacy.claude.com/en/articles/9015913-how-to-get-support.
