# Mac App Store preparation

The GitHub ZIP uses Developer ID signing and is not an App Store upload. `AppStore/project.yml` generates a separate Xcode project with sandboxing, its own bundle ID, an app icon, and a privacy manifest. The existing GitHub build remains separate.

Generate the project with `xcodegen generate --spec AppStore/project.yml`, then open `AppStore/AIMonitorAppStore.xcodeproj` in Xcode. Select your team, confirm the bundle ID, and let Xcode manage signing. Use Product > Archive and Organizer > Distribute App > App Store Connect after completing validation.

Alternatively, run `./scripts/build-app-store.sh` after configuring signing. Pass `-allowProvisioningUpdates` if Xcode needs to create or download signing assets for your signed-in developer account. It writes `dist/AI-Monitor-AppStore.xcarchive`. This command does not upload or accept agreements.

The sandbox allows outgoing provider requests, a temporary incoming loopback listener for sign-in, and read-only access to user-selected authentication files. Direct automatic CLI-file import is omitted from this build. Users can choose the file explicitly instead.

The App Store bundle uses `com.afzalh.aimonitor`, separate from the GitHub app's `com.local.ai-monitor`. Its sandbox data and credentials must be verified with a clean test account. Do not promise automatic migration from the GitHub app.

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
