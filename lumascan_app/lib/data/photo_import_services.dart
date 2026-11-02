import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';

import '../domain/models.dart';
import '../domain/photo_import.dart';
import '../imaging/corner_model.dart';
import '../imaging/corner_worker.dart';
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

/// Decodes a small copy of the photo off the UI thread and finds the page
/// in it. With smart scanning (Pro) and a [worker], the corner model
/// ([CornerModel]) is asked first, as in the camera preview, and the
/// hand-made [detectPageQuad] only when the model is not sure of every
/// corner or cannot run. This is what every scan path uses on a photo: the
/// shot just taken, gallery and shared imports, ID card sides, Auto crop
/// and the crop screen's auto detect.
class DetectorPhotoAnalyzer implements PhotoAnalyzer {
  /// Long edge of the copy used for detection; the detector works at 320.
  static const decodeSize = 640;

  /// [smart] is the Pro plan's smarter page search.
  DetectorPhotoAnalyzer({this.smart = true, this.worker});

  final bool smart;

  /// The app's [CornerWorker], when the model may be used.
  final Future<CornerWorker?> Function()? worker;

  @override
  Future<CropQuad?> analyze(String path) async {
    final smart = this.smart;
    final w = smart ? await worker?.call() : null;
    if (w != null) return w.run(PhotoCornerJob(path));
    return Isolate.run(() => PhotoCornerJob(path, smart: smart).run(null));
  }
}

/// One photo on disk for the [CornerWorker]: its page outline.
class PhotoCornerJob extends CornerJob<CropQuad?> {
  const PhotoCornerJob(this.path, {this.smart = true});

  final String path;
  final bool smart;

  @override
  CropQuad? run(CornerModel? model) {
    final image = RgbImage.decode(File(path).readAsBytesSync(), maxDimension: DetectorPhotoAnalyzer.decodeSize);
    return (smart ? model?.find(image) : null) ?? detectPageQuad(image, smart: smart);
  }
}
