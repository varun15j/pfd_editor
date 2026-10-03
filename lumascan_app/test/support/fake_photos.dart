import 'package:lumascan/data/page_store.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/photo_import.dart';

/// Returns [photos] on every pick and counts the picks.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker([this.photos = const []]);

  List<PickedPhoto> photos;
  int picks = 0;

  @override
  Future<List<PickedPhoto>> pick() async {
    picks++;
    return photos;
  }
}

/// Finds the same page in every photo, and treats names in [unreadable] as
/// broken files.
class FakePhotoAnalyzer implements PhotoAnalyzer {
  FakePhotoAnalyzer({this.unreadable = const {}});

  static const quad = CropQuad(NormPoint(0.1, 0.1), NormPoint(0.9, 0.1), NormPoint(0.9, 0.9), NormPoint(0.1, 0.9));

  final Set<String> unreadable;

  @override
  Future<CropQuad?> analyze(String path) async {
    if (unreadable.any(path.endsWith)) throw const FormatException('Unsupported or corrupt image');
    return quad;
  }
}

/// Keeps "copied" originals at their source path, so widget tests never touch
/// the disk.
class NoCopyPageStore extends PageStore {
  @override
  Future<String> importOriginal(String sourcePath, String id) async => sourcePath;
}
