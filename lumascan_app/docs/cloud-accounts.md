# Cloud accounts (Settings > Accounts)

Settings > Accounts lets the user connect cloud storage and import PDF and
Word files from it into the Library. It is read-only: LumaScan never uploads,
changes, deletes or syncs anything. Connecting is optional; the app works the
same without it. Varun asked for this on 2026-10-13, as an exception to the
local-first Release 1 decision (cloud upload, sync and share links stay P1).

## How it is built

- `lib/domain/cloud_storage.dart`: the `CloudStorageProvider` interface. Each
  service is its own class behind it.
- `lib/data/cloud/`: `GoogleDriveProvider` (Google Sign-In, Drive API v3),
  `OneDriveProvider` (AppAuth with PKCE, Microsoft Graph) and
  `ICloudDriveProvider` (the iOS Files picker; Apple has no iCloud Drive API
  for apps). The REST parts (`GoogleDriveApi`, `OneDriveApi`) are separate
  from sign-in so they are tested with a fake HTTP client.
- `lib/features/cloud/`: the Accounts screen, the browse screen, the folder
  picker and `CloudImporter`. A PDF is copied into the exports folder and
  added with `LibraryController.addPdf`; a Word file goes through
  `WordService.wordToPdf`, the same path as Create > Word file. A Google Docs
  document is exported by Drive as a PDF.
- The OneDrive refresh token and the account names are kept in
  `flutter_secure_storage`. Google keeps its own sign-in.

## IDs to create

All values are public client IDs; no client secret is used. There are two
sets in `lib/app/cloud_config.dart`: `debugCloudClientIds` for debug builds
(`flutter run`, debug APKs) and `releaseCloudClientIds` for release and
profile builds. Paste each ID there, or pass it with `--dart-define`, which
wins for that build. A provider without its IDs shows "Not set up in this
build yet".

Package names: Android is `com.mobi.scanner`; the iOS bundle ID is
`com.lumascan.lumascan`.

The simplest setup is one Google Cloud project and one Microsoft app
registration per build type (for example "LumaScan debug" and "LumaScan").
The same IDs in both sets also work.

### Google Drive (Google Cloud console), for each build type

1. Create a project and enable the **Google Drive API**.
2. OAuth consent screen: add the scope
   `https://www.googleapis.com/auth/drive.readonly`. It is a restricted
   scope, so a public release needs Google's verification; test users work
   before that.
3. Credentials, three OAuth clients:
   - **Web application**: its client ID is `googleServerClientId`
     (Android needs it even without a server).
   - **Android**: package `com.mobi.scanner` and the SHA-1 of the key that
     signs that build: the debug keystore for debug, the release key for
     release. No value goes in the app. Get a SHA-1 with
     `cd lumascan_app/android; ./gradlew signingReport`. Until a release
     keystore is set up, release builds are signed with the debug key (see
     `android/app/build.gradle.kts`), so both SHA-1s are the same.
   - **iOS**: bundle ID `com.lumascan.lumascan`. Its client ID is
     `googleIosClientId`. Its reversed form
     (`com.googleusercontent.apps.<id>`) replaces the placeholder
     `GOOGLE_REVERSED_CLIENT_ID` in `ios/Flutter/Debug.xcconfig` (debug) or
     `ios/Flutter/Release.xcconfig` (release and profile).

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
