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

All values are public client IDs; no client secret is used. Put them in
`lib/app/cloud_config.dart`, or pass them with `--dart-define`. A provider
without its IDs shows "Not set up in this build yet".

### Google Drive (Google Cloud console)

1. Create a project and enable the **Google Drive API**.
2. OAuth consent screen: add the scope
   `https://www.googleapis.com/auth/drive.readonly`. It is a restricted
   scope, so a public release needs Google's verification; test users work
   before that.
3. Credentials, three OAuth clients:
   - **Web application**: its client ID is `LUMASCAN_GOOGLE_SERVER_CLIENT_ID`
     (Android needs it even without a server).
   - **Android**: package `com.lumascan.lumascan` and the SHA-1 of each
     signing key (debug and release). No value goes in the app.
   - **iOS**: bundle ID `com.lumascan.lumascan`. Its client ID is
     `LUMASCAN_GOOGLE_IOS_CLIENT_ID`, and its reversed form
     (`com.googleusercontent.apps.<id>`) replaces the placeholder URL scheme
     in `ios/Runner/Info.plist`.

### Microsoft OneDrive (Microsoft Entra admin center)

1. App registrations > New registration. Supported account types: accounts
   in any organizational directory and personal Microsoft accounts.
2. Authentication > Add a platform > **Mobile and desktop applications**,
   custom redirect URI `com.lumascan.lumascan://oauthredirect`.
3. API permissions (Microsoft Graph, delegated): `Files.Read`, `User.Read`,
   `offline_access`.
4. The Application (client) ID is `LUMASCAN_MICROSOFT_CLIENT_ID`.

### iCloud Drive

Nothing to create. On iPhone and iPad it opens the Files picker with the
phone's own Apple account; on Android it shows "Only on iPhone and iPad".
