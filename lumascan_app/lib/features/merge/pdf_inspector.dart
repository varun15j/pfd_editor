import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Why a PDF cannot be merged.
enum PdfProblem { locked, unreadable }

/// What opening a PDF showed: its page count, or the reason it cannot be
/// used. Never throws for a bad file, so a list can flag it and carry on.
class PdfInfo {
  const PdfInfo.ok(int this.pageCount) : problem = null;
  const PdfInfo.problem(PdfProblem this.problem) : pageCount = null;

  final int? pageCount;
  final PdfProblem? problem;
}

/// Opens a PDF only to count its pages and tell whether it can be read.
/// Behind an interface so merge tests do not need the PDFium engine.
abstract class PdfInspector {
  Future<PdfInfo> inspect(String path);
}

/// pdfrx (PDFium) inspector. A password-protected file is reported as locked
/// without asking for the password.
class PdfrxInspector implements PdfInspector {
  @override
  Future<PdfInfo> inspect(String path) async {
    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(path, passwordProvider: () async => null);
      try {
        final count = document.pages.length;
        return count == 0 ? const PdfInfo.problem(PdfProblem.unreadable) : PdfInfo.ok(count);
      } finally {
        await document.dispose();
      }
    } on PdfPasswordException {
      return const PdfInfo.problem(PdfProblem.locked);
    } on Object {
      return const PdfInfo.problem(PdfProblem.unreadable);
    }
  }
}

final pdfInspectorProvider = Provider<PdfInspector>((ref) => PdfrxInspector());
