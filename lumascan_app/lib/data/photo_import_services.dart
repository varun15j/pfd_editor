import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';

import '../domain/models.dart';
import '../domain/photo_import.dart';
import '../imaging/card_outline.dart';
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
    final w = await worker?.call();
    if (w != null) return w.run(PhotoCornerJob(path, smart: smart));
    return Isolate.run(() => PhotoCornerJob(path, smart: smart).run(null));
  }
}

/// The card in the ID card photo at [path], for a document [aspect] wide to
/// high, or null when none is found: the page [found] by the
/// [PhotoAnalyzer] or the card's printed outline ([findCardOutline]), in the
/// card's shape and, for a camera shot, close to the [guide] in size.
///
/// The page found is kept when it fits, as it is a card on a table, but
/// for an imported photo ([guide] null) where it is nearly all the frame.
/// That photo is often a photocopy or scan of a card, and what was found is
/// the sheet of paper (in the card's shape too when the photo is cropped
/// close), so the outline is looked for first there.
Future<CropQuad?> idCardCrop(String path, {required double aspect, CropQuad? found, CropQuad? guide}) =>
    Isolate.run(() {
      final image = RgbImage.decode(File(path).readAsBytesSync(), maxDimension: DetectorPhotoAnalyzer.decodeSize);
      bool fits(CropQuad? q) =>
          q != null &&
          cardShaped(q, image.width, image.height, aspect) &&
          (guide == null ? q.area >= 0.15 : isCardLike(q, guide));
      if (fits(found) && (guide != null || found!.area < 0.85)) return found;
      final outline = findCardOutline(image, aspect: aspect);
      if (fits(outline)) return outline;
      return fits(found) ? found : null;
    });

/// One photo on disk for the [CornerWorker]: its page outline.
class PhotoCornerJob extends CornerJob<CropQuad?> {
  const PhotoCornerJob(this.path, {this.smart = true});

  final String path;
  final bool smart;

  @override
  CropQuad? run(CornerModel? model) {
    final image = RgbImage.decode(File(path).readAsBytesSync(), maxDimension: DetectorPhotoAnalyzer.decodeSize);
    return model?.find(image) ?? detectPageQuad(image, smart: smart);
  }
}
