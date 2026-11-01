import '../../domain/id_masking.dart';
import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../pdf_edit/annotations.dart';

/// Auto mask, shared by the Markup screen and Batch Review: read a page on
/// the device, find its private numbers and turn them into masks.

/// The engine that can read where text is, or the reason it cannot run.
Future<(OcrLayoutEngine?, String?)> autoMaskEngine(OcrEngine engine) async {
  final capability = await engine.capability('en');
  if (engine is! OcrLayoutEngine || capability.readiness == OcrReadiness.unavailable) {
    return (null, capability.reason ?? 'ID numbers cannot be found on this device. Drag over a number to mask it.');
  }
  return (engine as OcrLayoutEngine, null);
}

/// The private numbers on [page]. It is read with its masks already in
/// place, so a number masked before is not found again.
Future<List<IdMatch>> findIdsOnPage(OcrLayoutEngine engine, ScanPage page) async {
  final layout = await engine.recognizeLayout(page, languageCode: 'en');
  return const IdNumberFinder().find(layout);
}

/// One mask per piece of each match: Xs over characters OCR read, a black
/// box over a number it could not.
List<MaskAnnotation> masksFor(List<IdMatch> found, String Function() newId) => [
  for (final m in found)
    for (final p in m.pieces)
      MaskAnnotation(
        id: newId(),
        left: p.left,
        top: p.top,
        right: p.right,
        bottom: p.bottom,
        label: m.kind.label,
        crosses: p.chars,
      ),
];

/// "Masked 2 numbers (Aadhaar number, Date of birth)." and a note about the
/// ones hidden with a black box because they could not be read.
String autoMaskSummary(List<IdMatch> found, {int pages = 1}) {
  final kinds = {for (final m in found) m.kind.label}.join(', ');
  final unreadable = found.where((m) => m.unreadable).length;
  final where = pages > 1 ? ' on $pages pages' : '';
  return [
    'Masked ${found.length} ${found.length == 1 ? 'number' : 'numbers'}$where ($kinds).',
    if (unreadable > 0)
      unreadable == 1
          ? 'One could not be read, so it is covered with a black box.'
          : '$unreadable could not be read, so they are covered with black boxes.',
    'Check before sharing.',
  ].join(' ');
}
