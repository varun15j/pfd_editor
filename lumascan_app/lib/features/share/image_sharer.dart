import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_sharer.dart';

/// Hands JPG files to the system share sheet, where they can be saved to the
/// gallery or sent. Behind an interface so tests do not need the plugin.
abstract class ImageSharer {
  /// Throws when the share sheet cannot be opened.
  Future<SendOutcome> send(List<String> paths, {Rect? origin});
}

class SharePlusImageSharer implements ImageSharer {
  @override
  Future<SendOutcome> send(List<String> paths, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [for (final p in paths) XFile(p, mimeType: 'image/jpeg')],
        sharePositionOrigin: origin,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? SendOutcome.dismissed : SendOutcome.sent;
  }
}

final imageSharerProvider = Provider<ImageSharer>((ref) => SharePlusImageSharer());
