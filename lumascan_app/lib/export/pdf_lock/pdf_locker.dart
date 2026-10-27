import 'dart:io';
import 'dart:isolate';

import '../../data/page_store.dart';
import '../../pdf_edit/pdf_saver.dart';
import 'pdf_encryption.dart';

export 'pdf_encryption.dart' show PdfAlreadyLockedException, minPasswordLength;

/// Makes password-protected copies of PDFs (Pro). The copy needs the
/// password to open in any PDF reader. The saved PDF is never changed, so
/// the Library, thumbnails and every tool keep working on it.
class PdfLocker {
  PdfLocker(this._store);

  final PageStore _store;

  /// "Lease (locked).pdf" for "Lease" or "Lease.pdf".
  static String lockedName(String name) {
    final stem = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
    return PdfEditSaver.safeFileName('$stem (locked)');
  }

  /// Writes a locked copy of [sourcePath] for sending and returns it.
  Future<File> lock({required String sourcePath, required String name, required String password}) async {
    if (password.length < minPasswordLength) throw ArgumentError('Password too short');
    final source = await File(sourcePath).readAsBytes();
    final locked = await Isolate.run(() => lockPdfBytes(source, password));
    return _store.writeFileAtomically('share/${lockedName(name)}', locked);
  }
}
