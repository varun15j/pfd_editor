// OAuth settings for the cloud accounts in Settings > Accounts.
//
// These are public client IDs for an installed app, not secrets: no client
// secret is used anywhere, and sign-in uses PKCE. Debug builds use the debug
// set and release (and profile) builds the release set, so the debug app can
// sign in against test OAuth clients while the store build uses its own.
//
// Paste each ID between the quotes below, or pass it at build time instead
// (a --dart-define value wins over the pasted one for that build):
//
//   flutter run --dart-define=LUMASCAN_MICROSOFT_CLIENT_ID=...
//
// A provider whose IDs are empty shows "Not set up in this build yet" in
// Settings > Accounts instead of a Connect button. How to create the IDs is
// in docs/cloud-accounts.md. Google Drive and iCloud Drive need no IDs: they
// use the system file picker.
import 'package:flutter/foundation.dart';

/// The client IDs used by one kind of build.
class CloudClientIds {
  const CloudClientIds({required this.microsoftClientId});

  /// Microsoft app registration's Application (client) ID.
  final String microsoftClientId;
}

// Paste your IDs here.

/// Used by `flutter run` and debug APKs, signed with the debug keystore.
const debugCloudClientIds = CloudClientIds(
  microsoftClientId: '', // Application (client) ID, a GUID
);

/// Used by release and profile builds, signed with the release key.
const releaseCloudClientIds = CloudClientIds(
  microsoftClientId: '', // Application (client) ID, a GUID
);

/// The set for a debug build when [debug] is true, otherwise the release set.
CloudClientIds cloudClientIdsFor({required bool debug}) => debug ? debugCloudClientIds : releaseCloudClientIds;

abstract final class CloudConfig {
  static final _ids = cloudClientIdsFor(debug: kDebugMode);

  // Microsoft OneDrive (Microsoft Entra admin center > App registrations).

  static String get microsoftClientId =>
      _define(const String.fromEnvironment('LUMASCAN_MICROSOFT_CLIENT_ID'), _ids.microsoftClientId);

  /// Registered under "Mobile and desktop applications" in each app
  /// registration. The scheme matches the Android package name and must match
  /// appAuthRedirectScheme in android/app/build.gradle.kts; iOS needs no
  /// entry for it.
  static const microsoftRedirectUri = 'com.mobi.scanner://oauthredirect';

  /// "common" accepts both personal and work or school accounts.
  static const microsoftTenant = 'common';

  /// Read-only file access, the user's name, and a refresh token so the
  /// account stays connected between launches.
  static const microsoftScopes = ['Files.Read', 'User.Read', 'offline_access'];

  static String _define(String fromBuild, String pasted) => fromBuild.isNotEmpty ? fromBuild : pasted;
}
