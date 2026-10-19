# OpenAI quota integration request

Historical draft for OpenAI Support. Not sent. The owner chose to proceed with App Review using the existing integration.

Subject: Supported read-only Codex quota access for QuotaBar for AI

I maintain QuotaBar for AI, a free, open-source macOS menu bar app, and am preparing a Mac App Store release. Source: https://github.com/AfzalH/ai-monitor

Each user connects their own ChatGPT subscription. The app displays Codex usage percentages, reset times, and available banked resets. It does not send prompts, run inference, or read conversations. Credentials stay in the user's macOS Keychain and requests go directly to OpenAI.

The current implementation uses the Codex CLI OAuth client ID and reads `/backend-api/wham/usage` and `/backend-api/wham/rate-limit-reset-credits`. We want to replace this with a supported integration under QuotaBar's own app identity.

The Sign in with ChatGPT documentation describes dynamic client registration for open-source apps. The Codex app-server documentation also describes `account/rateLimits/read`, including reset credits. Could you confirm the supported way for QuotaBar to authenticate and read those limits without requesting inference access? Can a token issued to QuotaBar through dynamic registration read the user's Codex subscription limits, and through which documented interface?

Please clarify any registration, scope, polling, or distribution requirements for this read-only use case, including distribution through the Mac App Store. If the current backend endpoints are not supported for third-party clients, please identify the supported replacement.

Please route this to the team responsible for Sign in with ChatGPT or Codex integrations if necessary. We are seeking guidance specific to quota monitoring, not authorization to consume the user's subscription for model requests.
