# Cloud accounts (Settings > Accounts)

Settings > Accounts lets the user connect cloud storage and import PDF and
Word files from it into the Library. It is read-only: LumaScan never uploads,
changes, deletes or syncs anything. Connecting is optional; the app works the
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

### Google Drive

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
