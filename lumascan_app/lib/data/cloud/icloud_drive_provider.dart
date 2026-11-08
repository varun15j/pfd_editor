import 'dart:io';

import '../../domain/cloud_storage.dart';
import 'system_file_picker.dart';

/// iCloud Drive. Apple offers apps no API to browse the user's iCloud Drive,
/// so this opens the system Files picker, which shows iCloud Drive with the
/// iPhone's own Apple account. There is nothing to connect.
class ICloudDriveProvider extends CloudStorageProvider {
  @override
  CloudProviderId get id => CloudProviderId.iCloudDrive;

  @override
  CloudAvailability get availability =>
      Platform.isIOS ? CloudAvailability.ready : CloudAvailability.unsupportedPlatform;

  @override
  bool get usesSystemPicker => true;

  @override
  Future<CloudAccount?> restore() async => null;

  @override
  Future<CloudAccount> connect() => throw UnsupportedError('iCloud Drive uses the Apple account on this iPhone');

  @override
  Future<void> disconnect() async {}

  @override
  Future<PickedCloudFile?> pickFile() => pickDocumentWithSystemPicker();
}
