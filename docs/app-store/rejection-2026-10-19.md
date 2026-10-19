# App Review rejection, 19 October 2026

Apple rejected version 1.0.0 build 15 under guideline 2.4.5. Automated analysis found the `com.apple.security.network.server` entitlement without matching functionality. Apple asks us to remove unused entitlements or explain why the app needs this entitlement in a reply and App Review Information.

The entitlement is required for browser OAuth callbacks. `OAuthCallbackServer` binds an `NWListener` to `127.0.0.1`. Codex uses port 1455 with 1457 as a fallback. Claude uses an OS-assigned port. The callback paths are `/auth/callback` and `/callback`, respectively. The app validates the path and OAuth state, then exchanges the code using PKCE. The listener closes after the callback, cancellation, failure, or a ten-minute timeout. Routine quota refreshes do not start it.

Reviewer steps: open the menu-bar popout, open Settings, add a Claude or Codex account, and click Sign in to Claude or Sign in to Codex. Completing the callback requires a supported provider account. The temporary listener receives the browser redirect after authentication. The sandbox needs the server entitlement to accept that connection, even though it is local to this Mac. Outgoing provider requests use the separate network client entitlement.

Keep the entitlement. The explanation was saved in App Review Information on both records. With owner authorization, the reply was sent to Apple on 19 October at 13:05 CEST. The replacement record includes the explanation in App Review Information.

The replacement bundle ID is `com.srizon.quotabar`. The existing rejected record uses `com.afzalh.aimonitor`; its bundle ID cannot change after a build upload. The replacement record must include the same explanation.

The replacement App Store record is `6824478425`, named QuotaBar for AI. The rejected record was renamed QuotaBar for AI Legacy to release the name. Version 1.0.0 build 20 was archived with both architectures and uploaded successfully on 19 October. Build 20 is selected and saved on the replacement record, with Sign-in required unchecked and the authorized review contact details entered. Free pricing and availability in all 175 regions are configured. The privacy URL is saved. The Data Not Collected declaration is published with owner confirmation. The age rating is saved as 4+, with regional equivalents. The owner completed and saved the content-rights declaration on the replacement record. The legacy record is set to manual release to prevent automatic publication of the old build.

Version 1.0.0 build 20 was submitted on 19 October 2026 at 13:25 CEST. App Store Connect confirms Waiting for Review. Submission ID: `efc014ea-2667-4781-bf4a-b8e2c85dd46c`. The replacement version is configured to release automatically after approval.
