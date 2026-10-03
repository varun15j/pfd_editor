import 'package:flutter/foundation.dart';

import 'models.dart';

/// A photo the user picked, before it is checked or copied.
@immutable
class PickedPhoto {
  const PickedPhoto({required this.path, required this.name});

  final String path;

  /// File name shown when the photo can't be read.
  final String name;
}

/// Opens the system photo picker for several images (C2).
abstract interface class PhotoPicker {
  /// Returns the picked photos, or an empty list when the user cancels.
  Future<List<PickedPhoto>> pick();
}

/// Checks that a photo can be decoded and finds the page in it.
abstract interface class PhotoAnalyzer {
  /// Returns the page's corners, or null when no page stands out. Throws
  /// [FormatException] when the file is not a readable image.
  Future<CropQuad?> analyze(String path);
}

/// What an import added and which photos had to be left out.
@immutable
class PhotoImportResult {
  const PhotoImportResult({required this.added, this.unreadable = const []});

  final int added;

  /// Names of photos that could not be read.
  final List<String> unreadable;
}
