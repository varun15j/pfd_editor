import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';

import '../domain/models.dart';
import '../domain/photo_import.dart';
import '../imaging/page_detector.dart';
import '../imaging/rgb_image.dart';

/// [PhotoPicker] backed by file_picker: its image picker for the gallery,
/// and the file browser limited to image types for files.
class FilePickerPhotoPicker implements PhotoPicker {
  static const imageExtensions = ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'bmp'];

  @override
  Future<List<PickedPhoto>> pick({bool fromFiles = false}) async {
    final files = fromFiles
        ? await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: imageExtensions)
        : await FilePicker.pickFiles(type: FileType.image);
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

  /// [smart] is the Pro plan's smarter page search.
  DetectorPhotoAnalyzer({this.smart = true});

  final bool smart;

  @override
  Future<CropQuad?> analyze(String path) {
    final smart = this.smart;
    return Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      return detectPageQuad(RgbImage.decode(bytes, maxDimension: _decodeSize), smart: smart);
    });
  }
}
