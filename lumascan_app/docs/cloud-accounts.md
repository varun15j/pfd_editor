# Cloud accounts (Settings > Accounts)

Settings > Accounts lets the user connect cloud storage and import PDF and
Word files from it into the Library. Importing is read-only. Saving exports
to Google Drive is separate, in Settings > Sync (below). Connecting is optional; the app works the
same without it. Varun asked for this on 2026-10-13, as an exception to the
local-first Release 1 decision (cloud upload, sync and share links stay P1).

## How it is built

- `lib/domain/cloud_storage.dart`: the `CloudStorageProvider` interface. Each
  service is its own class behind it.
- `lib/data/cloud/`: `GoogleDriveProvider` (the system file picker),
  `OneDriveProvider` (AppAuth with PKCE, Microsoft Graph) and
  `ICloudDriveProvider` (the iOS Files picker; Apple has no iCloud Drive API
  for apps). Both picker providers share `pickDocumentWithSystemPicker` in
  `system_file_picker.dart`. `OneDriveApi` is separate from sign-in so it is
  tested with a fake HTTP client.
- `lib/features/cloud/`: the Accounts screen, the browse screen, the folder
  picker and `CloudImporter`. A PDF is copied into the exports folder and
  added with `LibraryController.addPdf`; a Word file goes through
  `WordService.wordToPdf`, the same path as Create > Word file.
- The OneDrive refresh token and the account names are kept in
  `flutter_secure_storage`.

## IDs to create

All values are public client IDs; no client secret is used. There are two
sets in `lib/app/cloud_config.dart`: `debugCloudClientIds` for debug builds
(`flutter run`, debug APKs) and `releaseCloudClientIds` for release and
profile builds. Paste each ID there, or pass it with `--dart-define`, which
wins for that build. A provider without its IDs shows "Not set up in this
build yet".

Package names: Android is `com.mobi.scanner`; the iOS bundle ID is
`com.lumascan.lumascan`.

The simplest setup is one Microsoft app registration per build type (for
example "LumaScan debug" and "LumaScan"). The same ID in both sets also
works.

### Google Drive import

Nothing to create. Since 2026-11-08 Google Drive opens the system file
picker instead of signing in. Android lists Google Drive in its picker; on
iPhone and iPad it appears in the Files picker once the Google Drive app is
installed. The phone's own Google sign-in is used and only the picked file
reaches the app, so the app asks Google for no Drive scope.

Why: the earlier browse screen needed `drive.readonly`, a restricted scope.
A public Play Store or App Store release with it needs Google's OAuth
verification plus a yearly paid security assessment (CASA). Even
`drive.file` would still need a Google sign-in, OAuth clients and brand
verification, and on Android it only works with Google's web Picker. The
system picker needs none of that.

Trade-off: native Google Docs, Sheets and Slides files are not offered,
because the picker only shows PDF and Word files. Users can save a Google
Doc as PDF or Word in Drive first.

### Google Drive sync (Settings > Sync), for each build type

Sync saves every exported PDF to the user's own Google Drive, in a folder
named after the app (`appName`). Varun asked for it on 2026-11-08, as a
change to the local-first Release 1 decision. It uses the `drive.file`
scope: the app sees only the folder and files it made, never the rest of the
user's Drive. Google lists `drive.file` as non-sensitive, so a public
release needs brand verification only (app name, logo, privacy policy URL,
verified domain), not the restricted-scope security assessment.

1. Create a project and enable the **Google Drive API**.
2. OAuth consent screen: add the scope
   `https://www.googleapis.com/auth/drive.file`. Until brand verification
   is done, add testers as test users.
3. Credentials, three OAuth clients:
   - **Web application**: its client ID is `googleServerClientId`
     (Android needs it even without a server).
   - **Android**: package `com.mobi.scanner` and the SHA-1 of the key that
     signs that build: the debug keystore for debug; for Play Store builds,
     the **app signing key** SHA-1 from Play Console > Setup > App signing
     (and the upload key's SHA-1 for builds you install yourself). No value
     goes in the app. Get a local SHA-1 with
     `cd lumascan_app/android; ./gradlew signingReport`.
   - **iOS**: bundle ID `com.lumascan.lumascan`. Its client ID is
     `googleIosClientId`. Its reversed form
     (`com.googleusercontent.apps.<id>`) replaces the placeholder
     `GOOGLE_REVERSED_CLIENT_ID` in `ios/Flutter/Debug.xcconfig` (debug) or
     `ios/Flutter/Release.xcconfig` (release and profile).

How it works (`lib/features/cloud/drive_sync.dart`,
`lib/data/cloud/google_drive_backup.dart`):
- Settings > Sync has the account, a **Sync** switch and a **Sync using
  cellular data** switch (off by default, so uploads wait for Wi-Fi).
- After an export, the file joins a queue kept in `flutter_secure_storage`
  and uploads when sync may run: sync on, online, and on Wi-Fi unless
  cellular data is allowed. The queue is retried when the connection changes
  (`connectivity_plus`), when a switch changes, at launch and with "Sync now".
- Exporting the same scan again replaces its Drive file instead of adding a
  copy. Files already in Drive are never deleted, also not on disconnect.
- Uploads never show a Google consent screen on their own; an expired
  sign-in shows "Connect Google Drive again".

The export result also has **Save to Google Drive or Files**, which opens the
system save screen (`FilePicker.saveFile`). Google Drive shows there when its
app is installed; it needs no sign-in or IDs.

### Microsoft OneDrive (Microsoft Entra admin center), for each build type

1. App registrations > New registration. Supported account types: accounts
   in any organizational directory and personal Microsoft accounts.
2. Authentication > Add a platform > **Mobile and desktop applications**,
   custom redirect URI `com.mobi.scanner://oauthredirect`.
3. API permissions (Microsoft Graph, delegated): `Files.Read`, `User.Read`,
   `offline_access`.
4. The Application (client) ID is `microsoftClientId`.

### iCloud Drive

Nothing to create. On iPhone and iPad it opens the Files picker with the
phone's own Apple account; on Android it shows "Only on iPhone and iPad".
