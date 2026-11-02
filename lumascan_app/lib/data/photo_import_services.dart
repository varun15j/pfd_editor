import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../domain/models.dart';
import '../domain/photo_import.dart';
import '../imaging/corner_model.dart';
import '../imaging/rgb_image.dart';
import 'corner_worker.dart';

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

/// Decodes a small copy of the photo off the UI thread and finds the page
/// in it ([findPage]): with the corner model in [worker] first, when there
/// is one, then the hand-made detector. Every photo goes through here:
/// camera shots, imports, ID cards, crop and auto crop.
class DetectorPhotoAnalyzer implements PhotoAnalyzer {
  /// Long edge of the copy used for detection; the detector works at 320.
  static const _decodeSize = 640;

  /// [smart] is the Pro plan's smarter page search, the corner model
  /// included.
  DetectorPhotoAnalyzer({this.smart = true, Future<CornerWorker?>? worker}) : _worker = worker ?? Future.value();

  final bool smart;
  final Future<CornerWorker?> _worker;

  @override
  Future<CropQuad?> analyze(String path) => runCornerJob(_worker, _photoJob(path, smart));
}

CornerJob<CropQuad?> _photoJob(String path, bool smart) =>
    (model) => findPage(
      RgbImage.decode(File(path).readAsBytesSync(), maxDimension: DetectorPhotoAnalyzer._decodeSize),
      smart: smart,
      model: model,
    );
