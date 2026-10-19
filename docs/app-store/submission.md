# Mac App Store preparation

The GitHub ZIP uses Developer ID signing and is not an App Store upload. `AppStore/project.yml` generates a separate Xcode project with sandboxing, its own bundle ID, an app icon, and a privacy manifest. The existing GitHub build remains separate.

Generate the project with `xcodegen generate --spec AppStore/project.yml`, then open `AppStore/AIMonitorAppStore.xcodeproj` in Xcode. Select your team, confirm the bundle ID, and let Xcode manage signing. Use Product > Archive and Organizer > Distribute App > App Store Connect after completing validation.

Alternatively, run `./scripts/build-app-store.sh` after configuring signing. Pass `-allowProvisioningUpdates` if Xcode needs to create or download signing assets for your signed-in developer account. It writes `dist/AI-Monitor-AppStore.xcarchive`. This command does not upload or accept agreements.

The sandbox allows outgoing provider requests, a temporary incoming loopback listener for sign-in, and read-only access to user-selected authentication files. Direct automatic CLI-file import is omitted from this build. Users can choose the file explicitly instead.

Both build variants now target `com.srizon.quotabar`, with Keychain service `com.srizon.quotabar.credentials`. The rejected App Store record uses `com.afzalh.aimonitor` and cannot accept builds with the new ID. The new ID is registered and the replacement App Store record is `6824478425`. Version 1.0.0 build 20 has been uploaded and selected on that record.

The Developer ID app imports known preferences from `com.local.ai-monitor` once and retains its existing account-list location. When a credential is first read, it copies a readable legacy Keychain entry into the new service without deleting the original. If macOS denies access, reconnect that account. The App Store sandbox cannot automatically import the old app's container or the Developer ID app's files; verify it with a clean test account. The new App Store record also needs its own signing and Xcode Cloud setup. Launch-at-login registration does not transfer between bundle IDs. Remove the old login item and enable it again for the updated app.

## Submission prerequisites

- Register the explicit App ID and create the App Store Connect app record.
- Obtain App Store distribution signing and a matching provisioning profile. Developer ID signing alone is insufficient.
- Test the signed sandboxed build, including external-browser callbacks, Keychain save/read/delete, selected-file import, launch at login, and clean launch.
- Confirm permission for provider integrations under App Review guideline 5.2.2. Public CLI client IDs do not themselves establish permission for a third-party App Store app.
- Publish and verify privacy/support URLs; check privacy labels against the final build.
- Capture screenshots from the sandboxed build at Apple's accepted Mac dimensions, such as 1280×800 or 1440×900. Existing README window crops do not meet those dimensions.
- Complete contact details, pricing, availability, age rating, content rights, encryption, and any required business declarations in App Store Connect.
- Upload and validate through Xcode Organizer or Transporter. Choose the processed build before submitting for review.

References: [Distribution preparation](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Xcode Cloud

The shared Xcode project and AIMonitor scheme are committed so Xcode Cloud can discover them. Regenerate with `xcodegen generate --spec AppStore/project.yml` after changing project.yml or adding source files, and commit the generated project changes. User-specific Xcode state and signing assets remain ignored.

The initial workflow archives the macOS app when main changes. It does not automatically submit App Review or distribute to testers. The SwiftPM test suite is separate from the Xcode scheme.

## Current review status

Apple rejected build 15 under guideline 2.4.5 because its automated analysis found the server entitlement without matching functionality. The entitlement is needed for browser sign-in. The [rejection response](rejection-2026-10-19.md) records the implementation evidence and reply sent to Apple. The replacement record includes the expanded explanation in App Review Information. Build 20 is selected. Free pricing, worldwide availability, the privacy URL, and review contact details are saved. Data Not Collected is published with owner confirmation, and the age rating is saved as 4+, with regional equivalents. The owner completed and saved the content-rights declaration on the replacement record. The new record also needs its Xcode Cloud workflow verified.

Version 1.0.0 build 20 was submitted on 19 October 2026 at 13:25 CEST and is Waiting for Review. Submission ID: `efc014ea-2667-4781-bf4a-b8e2c85dd46c`. Automatic release after approval is enabled.
