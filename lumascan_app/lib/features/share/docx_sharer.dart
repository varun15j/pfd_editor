import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_sharer.dart';

/// Hands a Word (.docx) file to the system share sheet. Behind an interface
/// so tests do not need the plugin.
abstract class DocxSharer {
  /// Throws when the share sheet cannot be opened.
  Future<SendOutcome> send(String path, {Rect? origin});
}

class SharePlusDocxSharer implements DocxSharer {
  static const mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: origin,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? SendOutcome.dismissed : SendOutcome.sent;
  }
}

final docxSharerProvider = Provider<DocxSharer>((ref) => SharePlusDocxSharer());
