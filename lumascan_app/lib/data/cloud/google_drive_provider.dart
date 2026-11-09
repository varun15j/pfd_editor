import 'dart:io';

import '../../domain/cloud_storage.dart';
import 'system_file_picker.dart';

/// Google Drive through the system file picker.
///
/// Android lists Google Drive in its document picker, and iOS lists it in
/// the Files picker once the Google Drive app is installed. Both use the
/// phone's own Google sign-in and hand over only the file the user picks,
/// so the app signs in to nothing and asks Google for no Drive scope. That
/// keeps the store release clear of Google's restricted-scope verification
/// and security assessment, which the earlier drive.readonly browse screen
/// needed.
class GoogleDriveProvider extends CloudStorageProvider {
  @override
  CloudProviderId get id => CloudProviderId.googleDrive;

  @override
  CloudAvailability get availability =>
      Platform.isAndroid || Platform.isIOS ? CloudAvailability.ready : CloudAvailability.unsupportedPlatform;

  @override
  bool get usesSystemPicker => true;

  @override
  Future<CloudAccount?> restore() async => null;

  @override
  Future<CloudAccount> connect() => throw UnsupportedError('Google Drive uses the Google account on this phone');

  @override
  Future<void> disconnect() async {}

  @override
  Future<PickedCloudFile?> pickFile({void Function()? onFetching}) =>
      pickDocumentWithSystemPicker(onFetching: onFetching);
}
