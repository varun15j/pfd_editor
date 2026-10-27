# Share images into the app (Phase 2 item 22, Basic)

Pick photos in the gallery (or any app), tap **Share**, and the app is listed
in the share sheet. Choosing it opens the photo import screen with the shared
images, where the user sets the page order and auto-crop, then the pages open
as a new document. The document that was on screen stays on Home.

## How it works

Both platforms save each share as one folder in a **share inbox** on disk
before the app opens, so nothing is lost while Flutter starts or if the user
comes back later:

```
share_inbox/
  .incoming-1761578400123/   # still being copied, ignored by Dart
  1761578400456/001.jpg 002.jpg ...
```

Dart (`SharedImagesListener`, `DirectoryShareInbox`) checks the inbox when the
app starts and each time it comes back to the foreground, runs the images
through `importPhotosFlow`, then deletes the folder. It asks the platform for
the folder through the `lumascan/share_inbox` channel (`inboxPath`).

| | Android | iOS |
|---|---|---|
| Listed in the share sheet by | `ShareReceiverActivity` with `SEND` / `SEND_MULTIPLE` filters for `image/*` | `ShareExtension` target, activation rule: up to 100 images |
| Inbox folder | `filesDir/share_inbox` | `share_inbox` in the App Group `group.com.lumascan.lumascan` |
| Opens the app | Launch intent with `NEW_TASK`, like the launcher icon, so a running app comes to the front | `<bundle id>.share://import` URL scheme |
| Formats | Copied as sent | JPEG and PNG as sent; HEIC and others saved as JPEG |

Android reads only `content:` URIs from other apps; `file:` URIs and the app's
own providers are skipped so a share can't pull in the app's private files.

## iOS setup (one time, in Xcode)

The share extension and the app share files through an App Group, which has to
be allowed by the signing profile:

1. Open `ios/Runner.xcworkspace`, select the **Runner** target, Signing &
   Capabilities, pick your team. Do the same for **ShareExtension**.
2. Both targets already list the App Group `group.com.lumascan.lumascan` in
   their entitlements. With automatic signing Xcode registers it; otherwise
   add it to both App IDs in the Apple Developer portal.
3. To use another group name, change `SHARE_APP_GROUP` in the build settings
   of both targets.

Without the App Group the app still runs; the share sheet entry shows an error
and nothing is imported.

## Not covered yet

Sharing PDFs into the app (the other half of item 22) is not part of this
change.
