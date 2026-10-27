import 'package:flutter/foundation.dart';

import 'photo_import.dart';

/// Images shared into the app from another app's share sheet, such as the
/// photo gallery, waiting to be added as pages.
///
/// The native side saves each share as one batch on disk before the app
/// opens, so nothing is lost when Flutter is still starting or the user
/// finishes the import later.
abstract interface class ShareInbox {
  /// Batches waiting to be imported, oldest first.
  Future<List<SharedBatch>> pending();

  /// Deletes [batch] once it has been imported or turned down.
  Future<void> discard(SharedBatch batch);
}

/// The images from one share, in the order the other app sent them.
@immutable
class SharedBatch {
  const SharedBatch({required this.id, required this.photos});

  final String id;
  final List<PickedPhoto> photos;
}
