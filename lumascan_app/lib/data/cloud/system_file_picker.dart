import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/cloud_storage.dart';

/// Opens the system document picker for one PDF or Word file and copies it
/// out of the picker's cache, so it stays readable while it is imported.
/// Returns null when the user closes the picker.
///
/// Cloud apps installed on the phone (Google Drive, OneDrive, iCloud Drive)
/// show up in this picker on their own, with the phone's own sign-in, so the
/// app needs no account or permission of its own to read the chosen file.
Future<PickedCloudFile?> pickDocumentWithSystemPicker() async {
  final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'docx']);
  if (picked == null) return null;
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'cloud_imports'));
  await dir.create(recursive: true);
  final copy = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.name).toLowerCase()}');
  await picked.xFile.saveTo(copy);
  return PickedCloudFile(name: picked.name, file: File(copy));
}
