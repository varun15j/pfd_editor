// OAuth settings for the cloud accounts in Settings > Accounts.
//
// These are public client IDs for an installed app, not secrets: no client
// secret is used anywhere, and sign-in uses PKCE. Paste each ID between the
// quotes in the "Paste your IDs here" block below, or pass it at build time
// instead (a --dart-define value wins over the pasted one):
//
//   flutter run --dart-define=LUMASCAN_GOOGLE_SERVER_CLIENT_ID=...
//
// A provider whose IDs are empty shows "Not set up in this build yet" in
// Settings > Accounts instead of a Connect button. How to create the IDs,
// and the native files that need matching values, are in
// docs/cloud-accounts.md.

// Paste your IDs here.
const _googleWebClientId = ''; // "....apps.googleusercontent.com", type Web application
const _googleIosClientId = ''; // "....apps.googleusercontent.com", type iOS
const _microsoftClientId = ''; // Application (client) ID, a GUID

abstract final class CloudConfig {
  // Google Drive (Google Cloud console > APIs & Services > Credentials).

  /// OAuth client of type "Web application". Android's sign-in needs it as
  /// the server client ID even though LumaScan has no server.
  static const googleServerClientId = String.fromEnvironment(
    'LUMASCAN_GOOGLE_SERVER_CLIENT_ID',
    defaultValue: _googleWebClientId,
  );

  /// OAuth client of type "iOS" for bundle ID com.lumascan.lumascan. Its
  /// reversed form also goes in ios/Runner/Info.plist as a URL scheme.
  static const googleIosClientId = String.fromEnvironment(
    'LUMASCAN_GOOGLE_IOS_CLIENT_ID',
    defaultValue: _googleIosClientId,
  );

  /// Read-only access to every file in the user's Drive, so existing files
  /// can be listed. Google treats this as a restricted scope: a public
  /// release needs Google's app verification.
  static const googleDriveScopes = ['https://www.googleapis.com/auth/drive.readonly'];

  // Microsoft OneDrive (Microsoft Entra admin center > App registrations).

  /// Application (client) ID of an app registration that allows personal
  /// Microsoft accounts.
  static const microsoftClientId = String.fromEnvironment(
    'LUMASCAN_MICROSOFT_CLIENT_ID',
    defaultValue: _microsoftClientId,
  );

  /// Registered under "Mobile and desktop applications" for both platforms.
  /// The scheme must match appAuthRedirectScheme in
  /// android/app/build.gradle.kts.
  static const microsoftRedirectUri = 'com.lumascan.lumascan://oauthredirect';

  /// "common" accepts both personal and work or school accounts.
  static const microsoftTenant = 'common';

  /// Read-only file access, the user's name, and a refresh token so the
  /// account stays connected between launches.
  static const microsoftScopes = ['Files.Read', 'User.Read', 'offline_access'];
}
