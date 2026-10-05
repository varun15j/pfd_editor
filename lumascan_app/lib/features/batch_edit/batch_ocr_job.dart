import 'package:flutter/foundation.dart';

import '../../domain/models.dart';
import '../../domain/ocr.dart';

enum OcrPageStatus { waiting, running, done, empty, failed, cancelled }

/// One page's OCR result. [revision] is the page's recipe at the time, so a
/// later crop or rotation shows the text no longer matches the page.
@immutable
class OcrPageResult {
  const OcrPageResult({required this.pageId, required this.status, this.revision, this.text, this.error});

  final String pageId;
  final OcrPageStatus status;
  final String? revision;
  final String? text;
  final String? error;
}

/// Runs OCR over several pages one at a time (BE-07). Cancel stops pages
/// that have not started; images and finished results are kept. Failed pages
/// can be retried on their own.
class BatchOcrJob extends ChangeNotifier {
  BatchOcrJob({required this.engine, required List<ScanPage> pages, this.languageCode = 'en'})
    : _pages = pages,
      _results = {for (final p in pages) p.id: OcrPageResult(pageId: p.id, status: OcrPageStatus.waiting)};

  final OcrEngine engine;
  final String languageCode;
  final List<ScanPage> _pages;
  final Map<String, OcrPageResult> _results;
  bool _cancelled = false;
  bool _running = false;

  bool get running => _running;
  int get total => _pages.length;

  /// Results in document order.
  List<OcrPageResult> get results => [for (final p in _pages) _results[p.id]!];

  /// Pages that have finished, whatever the outcome.
  int get finished =>
      results.where((r) => r.status != OcrPageStatus.waiting && r.status != OcrPageStatus.running).length;

  /// The page being read now, counted from 1, or null.
  int? get currentNumber {
    final i = results.indexWhere((r) => r.status == OcrPageStatus.running);
    return i < 0 ? null : i + 1;
  }

  List<OcrPageResult> withStatus(OcrPageStatus status) => [
    for (final r in results)
      if (r.status == status) r,
  ];

  bool get complete => !_running && finished == total;

  Future<void> start() => _run(_pages);

  /// Runs the failed and cancelled pages again.
  Future<void> retry() => _run([
    for (final p in _pages)
      if (_results[p.id]!.status case OcrPageStatus.failed || OcrPageStatus.cancelled) p,
  ]);

  void cancel() {
    if (_running) _cancelled = true;
  }

  Future<void> _run(List<ScanPage> pages) async {
    if (_running || pages.isEmpty) return;
    _running = true;
    _cancelled = false;
    for (final p in pages) {
      _results[p.id] = OcrPageResult(pageId: p.id, status: OcrPageStatus.waiting);
    }
    notifyListeners();
    for (final page in pages) {
      if (_cancelled) {
        _results[page.id] = OcrPageResult(pageId: page.id, status: OcrPageStatus.cancelled);
        continue;
      }
      _set(OcrPageResult(pageId: page.id, status: OcrPageStatus.running));
      final revision = page.recipe.cacheKey;
      try {
        final text = await engine.recognize(page, languageCode: languageCode);
        _set(
          OcrPageResult(
            pageId: page.id,
            status: text.trim().isEmpty ? OcrPageStatus.empty : OcrPageStatus.done,
            revision: revision,
            text: text,
          ),
        );
      } catch (e) {
        _set(OcrPageResult(pageId: page.id, status: OcrPageStatus.failed, revision: revision, error: '$e'));
      }
    }
    _running = false;
    notifyListeners();
  }

  void _set(OcrPageResult result) {
    _results[result.pageId] = result;
    notifyListeners();
  }
}
