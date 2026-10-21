# Testing LumaScan on an iPhone from a Windows 11 PC

An iOS app can only be compiled with Xcode, and Xcode only runs on macOS. A Windows 11 PC cannot build the app, run
the iOS Simulator, or use `flutter run` against an iPhone. What Windows can do is start a build on a Mac somewhere
else, then put the finished app on the iPhone. This guide covers both halves.

**Recommendation for a personal test:** build an unsigned app on GitHub Actions with the workflow added in this
change (`.github/workflows/ios-unsigned-build.yml`), then sign and install it from Windows with **Sideloadly** and a
free Apple ID. It costs nothing. The catch is that the app stops opening after 7 days and must be installed again.
Move to TestFlight (section 2b) when you pay for the Apple Developer Program, or when someone else needs to test.

Prices and limits below were checked on 2026-10-21. Check them again before paying for anything.

## What the repo already has for iOS

| Setting | Where | Effect on an iPhone install |
| --- | --- | --- |
| Bundle ID `com.lumascan.lumascan` | `ios/Runner.xcodeproj/project.pbxproj` | Fine for sideloading. For TestFlight it must be registered to your Apple team. Bundle IDs are unique across all of Apple, so if someone else already owns it, pick another (for example `com.<yourname>.lumascan`) and change it in the project. |
| No `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE = Automatic` | `project.pbxproj` | The project is not tied to any Apple account, so it cannot be signed as is. That is why the workflow builds with `--no-codesign`, and Sideloadly or the CI service signs it later. |
| Deployment target iOS 16.0 | `project.pbxproj` | The iPhone needs iOS 16 or newer. iOS 16+ also needs **Developer Mode** switched on for sideloaded apps (section 3). |
| `NSCameraUsageDescription` | `ios/Runner/Info.plist` | Present. Without it iOS would close the app on the first scan. |
| No `Podfile` in git | `ios/` | Flutter creates the iOS dependency setup on the first build. The README notes that with Swift Package Manager, `permission_handler` reads the camera key from Info.plist. If a build ever uses CocoaPods instead, the camera permission is compiled out and the app always reports it as denied unless `PERMISSION_CAMERA=1` is added to the Podfile. The camera test in section 4 catches this. |
| No `NSPhotoLibraryUsageDescription` | `Info.plist` | Photo import uses the system picker, which needs no permission, so this is fine for a sideload. App Store Connect can reject an upload (error ITMS-90683) when a plugin links photo library code and the key is missing; add the key if a TestFlight upload is refused for that. |
| No `ITSAppUsesNonExemptEncryption` | `Info.plist` | Only matters for TestFlight: App Store Connect asks the export compliance question on every build until `ITSAppUsesNonExemptEncryption = NO` is added. |
| No `UIFileSharingEnabled` | `Info.plist` | The app's own folder does not show in the Files app. That is expected: PDFs leave the app through the share sheet ("Save to Files"). |

None of these block the free sideload path. The last three are small Info.plist changes to make before the first
TestFlight upload; they are left out of this change so it stays documentation only.

## 1. Getting an iOS build without a Mac

| Option | Cost | Good | Not so good |
| --- | --- | --- | --- |
| **GitHub Actions, macOS runner** | Free plan: 2,000 minutes a month for private repositories, but macOS minutes count 10x, so about 200 real macOS minutes (roughly 8 to 10 builds). Public repositories are free. Extra macOS time is $0.062 a minute, and a new account has a $0 spending limit, so jobs stop instead of charging you. | Already where the code is. No new account. The unsigned workflow needs no secrets. | Signing for TestFlight means handling certificates and profiles by hand (section 2b). |
| **Codemagic** | Personal account: 500 free macOS M2 minutes a month, reset on the 1st. After that $0.095 a minute. | Built for Flutter. Its automatic code signing creates and stores the certificate and profile for you, and it uploads to TestFlight in one step. | Another account to manage. Its automatic signing needs a paid Apple Developer account. |
| **Rented cloud Mac** (MacinCloud, AWS EC2 Mac, Scaleway and others) | Hourly or monthly. AWS EC2 Mac hosts have a 24 hour minimum, so even a short session pays for a day. | Full Xcode and macOS for debugging build errors. The iPhone is plugged into your PC, not the remote Mac, so you still install through TestFlight or a signed file. | You work over remote desktop, and you pay while it is idle. |
| **Borrowed Mac** | Free | The only way to get `flutter run` with hot reload, the debugger and Xcode device logs on a real iPhone. Free Apple ID signing works directly in Xcode. | Needs the Mac with you, and Flutter, Xcode and CocoaPods installed on it (Xcode alone is several GB). |

For testing from Windows, GitHub Actions is the starting point and Codemagic is the easiest route once TestFlight is
needed.

Sources: [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[macOS minute multiplier](https://cicdcalculator.com/github-actions-free-tier),
[Codemagic pricing](https://docs.codemagic.io/billing/pricing/),
[AWS EC2 Mac FAQ](https://aws.amazon.com/ec2/instance-types/mac/faqs/).

## 2. Getting the build onto the iPhone

### 2a. Free Apple ID with Sideloadly (recommended for a personal test)

- Cost: nothing. Any Apple ID works.
- The app is signed with a free development certificate that **expires after 7 days**. After that the app will not
  open until you install it again (your scans stay, because a reinstall over the old app keeps its data).
- At most **3 sideloaded apps** at once per device, and a free account can create only about 10 app IDs a week.
- Only devices you plug in yourself. You cannot send the app to someone else.
- No in-app purchases, push notifications or iCloud. LumaScan's Release 1 does not use any of these.

### 2b. Paid Apple Developer Program with TestFlight

- Cost: **US$99 a year**, or the local price Apple shows when you enrol. Enrolment can take a day or two to approve.
- Builds go to App Store Connect, and the TestFlight app installs them on the iPhone. A build lasts 90 days.
- Internal testers (up to 100 people on your App Store Connect team) need no Apple review. External testers need
  a short beta review.
- This is the path to use once others test, and it is the same pipeline the App Store release will use.

For one person testing their own phone, 2a is enough. Pay for 2b when you are ready to share builds or publish.

## 3. Step by step on Windows 11 (free path)

### On the PC, once

1. Install **iTunes** and **iCloud** from apple.com, not the Microsoft Store versions. Sideloadly needs the Apple
   device drivers they bring.
2. Install **Sideloadly** from sideloadly.io.
3. Plug the iPhone in with a cable, unlock it, and tap **Trust** on the iPhone. Sideloadly should now list the phone.

### On the iPhone, once

1. Settings > Privacy & Security > **Developer Mode** > On. The phone restarts and asks you to confirm. (This
   option only appears after a developer-signed app has been installed once, so you may need to do step 2 below
   first, then come back.)

### Each time you want a new build

1. On GitHub, open the repository > **Actions** > **iOS unsigned build** > **Run workflow**. Type the branch to
   build (default `feature/scan_save`; for batch edit type `feature/batch_edit`) and start it.
2. Wait for it to finish (the first run is the slowest because nothing is cached). Open the run and download
   **LumaScan-unsigned-ipa** from Artifacts. It comes as a `.zip`; unzip it to get `LumaScan-unsigned.ipa`.
3. Open Sideloadly, drag the `.ipa` in, type your Apple ID, and click **Start**. Sign in with your Apple ID
   password and the two-factor code when asked. Sideloadly signs the app with your free certificate and installs it.
4. On the iPhone: Settings > General > **VPN & Device Management**, tap your Apple ID under Developer App, and
   tap **Trust**. This is needed once per certificate, so roughly once a week.
5. Open LumaScan from the home screen.

The workflow builds in **release** mode. An iOS debug build only starts when a debugger is attached, so it would
close at once. This means the debug-only tools (Settings > Developer sample pages and book pages, and the debug
panel with the Plan row) are **not** in this build. Test scanning with real paper instead.

AltServer from altstore.io does the same job as Sideloadly on Windows if Sideloadly stops working.

### GitHub secrets for the free path

None. The workflow builds without signing, so it needs no Apple credentials. Your Apple ID is typed into
Sideloadly on your PC and never goes to GitHub.

### When you move to TestFlight (paid path)

Do these yourself; they need your Apple account and payment.

1. Enrol at developer.apple.com/programs ($99 a year).
2. In the developer portal, register the App ID `com.lumascan.lumascan` (or a new one if it is taken; then change
   `PRODUCT_BUNDLE_IDENTIFIER` in the project to match).
3. In App Store Connect, create the app (My Apps > + > New App) with that bundle ID.
4. In App Store Connect > Users and Access > Integrations > **App Store Connect API**, create a key with the App
   Manager role. Note the **Issuer ID** and **Key ID**, and download the `.p8` file. It can be downloaded only once.
5. Choose where to build:
   - **Codemagic (easier):** sign in with GitHub, add the repository, add the API key under Team integrations >
     Developer Portal, turn on automatic iOS code signing for App Store distribution, and turn on publishing to
     App Store Connect. Codemagic creates the signing certificate and profile itself. Project path is
     `lumascan_app`.
   - **GitHub Actions:** you make the signing files on Windows with OpenSSL (it comes with Git for Windows) and add
     them as repository secrets:

     ```bash
     # Create a key and a certificate request, then upload the .csr in the developer portal
     # (Certificates > + > Apple Distribution) and download distribution.cer.
     openssl genrsa -out dist.key 2048
     openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=<you>/CN=<your name>/C=IN"
     # Turn the downloaded certificate into a .p12 for the build Mac.
     openssl x509 -inform DER -in distribution.cer -out distribution.pem
     # -legacy keeps the .p12 readable by the macOS keychain on the build runner.
     openssl pkcs12 -export -legacy -inkey dist.key -in distribution.pem -out distribution.p12
     ```

     Then create an App Store provisioning profile for the App ID in the portal and download it. Secrets to add
     (Settings > Secrets and variables > Actions): `IOS_DIST_P12_BASE64`, `IOS_DIST_P12_PASSWORD`,
     `IOS_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`. Base64 a file in
     PowerShell with `[Convert]::ToBase64String([IO.File]::ReadAllBytes("distribution.p12"))`. A signed workflow
     that uses them is not part of this change.
6. Before the first upload, add `ITSAppUsesNonExemptEncryption = NO` to Info.plist (see the table at the top).
7. After the build uploads and finishes processing, add yourself as an internal tester in App Store Connect >
   TestFlight, install the **TestFlight** app on the iPhone, and install LumaScan from there.

Keep `dist.key`, the `.p12` and the `.p8` out of the repository.

## 4. Checking the app on the iPhone

Use real paper on a desk with normal light, and test on the iPhone itself; the iOS document camera does not run in
the Simulator.

### Permissions (do these first, on a fresh install)

| Check | Expected |
| --- | --- |
| Tap Scan for the first time | iOS asks for the camera with the text "LumaScan uses the camera to scan documents. Pages stay on this device." |
| Allow, then scan | The Apple document camera opens and finds page edges. |
| Delete the app, reinstall, tap Scan and choose **Don't Allow** | The app explains why it needs the camera and offers Try again. It must not crash. |
| Tap Scan again after denying | The app offers **Open Settings**, and the button opens LumaScan's page in iOS Settings. |
| Turn the camera on in iOS Settings and return | Scan works without restarting the app. |
| If the camera prompt never appears and the app always says it is denied | The camera permission was compiled out (see the Podfile row in the first table). This is a build problem, not a user setting. |
| Import from photos | The system photo picker opens with no permission prompt. |
| Open a PDF / Merge > pick a PDF | The Files picker opens. iCloud Drive and On My iPhone both work. |
| Export or share a PDF > Save to Files | The PDF appears in the Files app and opens there. |

### Release 1 features

| Area | What to try |
| --- | --- |
| Scan | Scan 3 to 5 pages in one go with auto capture. Check edges and that every page arrives in order. |
| Crop | Open a page, drag the corners, save. Check the page is straightened, and that crop can be changed again later. |
| Filters | Try each filter, hold to compare, use Apply to all. |
| Pages | Reorder by dragging, rotate, delete and undo. |
| Export PDF | Export with A4, Letter and fit to image, and each quality. Open the PDF in Files and check the page count and look. |
| Library | Close the app fully (swipe it away), reopen it, and check documents and drafts are still there. |
| PDF editor | Open a PDF, add a signature and markup, save, reopen. |
| Merge | Merge two PDFs and check the result. |
| Batch edit | Not on `feature/scan_save` yet. Build `feature/batch_edit` with the workflow to test it. |
| iPhone specifics | Rotate to landscape on each main screen, check the notch and home bar do not cover buttons, and check dark mode. |

Smart scanning features from the Pro and Gold plans need the debug panel's Plan row, which a release build does not
have, so they show the Basic behaviour here.

For crashes, the iPhone keeps reports in Settings > Privacy & Security > Analytics & Improvements > Analytics Data
(entries starting with `Runner`). Send those along with what you did.

## 5. What was not verified, and what only you can do

Not verified (this guide was written without a Mac or an iPhone):

- The workflow has not been run yet. The first run may need fixes, for example if `subosito/flutter-action` cannot
  find Flutter 3.47.6 or a plugin needs a newer Xcode than the runner has.
- Whether the app builds for iOS at all. No iOS build of LumaScan has been made so far.
- Whether `com.lumascan.lumascan` is still free to register with Apple.
- Whether `permission_handler` ends up built with Swift Package Manager or CocoaPods on the runner.
- Sideloadly and AltServer behaviour on your iOS version.
- Any iPhone-specific layout or performance issue.

Only you can do:

- Sign in to Sideloadly with your Apple ID and approve the two-factor prompt.
- Trust the developer certificate and turn on Developer Mode on the iPhone.
- Start the workflow on GitHub (and raise the Actions spending limit if you ever want more than the free minutes).
- Pay for and enrol in the Apple Developer Program, create the App ID, the App Store Connect app and the API key,
  and add the signing secrets, if you move to TestFlight.
