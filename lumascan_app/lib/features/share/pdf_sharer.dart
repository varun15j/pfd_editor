import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../export/pdf_shrinker.dart';
import '../../pdf_edit/pdf_edit_controller.dart';

/// What happened after handing a file to the system share sheet.
enum SendOutcome {
  /// The user picked an app, or the platform does not say (treated as handed over).
  sent,

  /// The share sheet was closed without choosing anything.
  dismissed,
}

/// Hands a file to the system share sheet. Behind an interface so tests do
/// not need the platform plugin.
abstract class PdfSharer {
  /// Throws when the share sheet cannot be opened.
  Future<SendOutcome> send(String path, {Rect? origin});
}

class SharePlusPdfSharer implements PdfSharer {
  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/pdf')],
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: origin,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? SendOutcome.dismissed : SendOutcome.sent;
  }
}

final pdfSharerProvider = Provider<PdfSharer>((ref) => SharePlusPdfSharer());

final pdfShrinkerProvider = Provider<PdfShrinker>(
  (ref) => PdfShrinker(ref.watch(pageStoreProvider), ref.watch(pdfRasterizerProvider)),
);
