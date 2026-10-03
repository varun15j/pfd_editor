import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';

import '../domain/models.dart';
import '../domain/photo_import.dart';
import '../imaging/page_detector.dart';
import '../imaging/rgb_image.dart';

/// [PhotoPicker] backed by file_picker's image picker.
class FilePickerPhotoPicker implements PhotoPicker {
  @override
  Future<List<PickedPhoto>> pick() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    return [
      for (final f in files)
        if (f.path != null) PickedPhoto(path: f.path!, name: f.name),
    ];
  }
}

/// Decodes a small copy of the photo off the UI thread and runs
/// [detectPageQuad] on it.
class DetectorPhotoAnalyzer implements PhotoAnalyzer {
  /// Long edge of the copy used for detection; the detector works at 320.
  static const _decodeSize = 640;

  @override
  Future<CropQuad?> analyze(String path) => Isolate.run(() {
    final bytes = File(path).readAsBytesSync();
    return detectPageQuad(RgbImage.decode(bytes, maxDimension: _decodeSize));
  });
}
