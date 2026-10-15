import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/cloud_storage.dart';

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
  Future<PickedCloudFile?> pickFile() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'docx']);
    if (picked == null) return null;
    // Copied out of the picker's cache so it stays readable while importing.
    final dir = Directory(p.join((await getTemporaryDirectory()).path, 'cloud_imports'));
    await dir.create(recursive: true);
    final copy = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.name).toLowerCase()}');
    await picked.xFile.saveTo(copy);
    return PickedCloudFile(name: picked.name, file: File(copy));
  }
}
