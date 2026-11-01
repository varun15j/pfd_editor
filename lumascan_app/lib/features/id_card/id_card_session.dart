import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../domain/id_copy.dart';
import '../../domain/library.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../export/pdf_exporter.dart';
import '../../imaging/id_copy_composer.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../library/library_controller.dart';
import '../pages/scan_controller.dart';

/// The ID copy on screen: the scan document's ID copy setup, or null when
/// the document is not one. It is kept with the document itself (see
/// [ScanDocInfo.idCopy]), so it is there again after the app restarts or the
/// document is opened from Home, and a side retaken anywhere stays that side.
final idCopyDraftProvider = NotifierProvider<IdCopyDraftNotifier, IdCopyDraft?>(IdCopyDraftNotifier.new);

class IdCopyDraftNotifier extends Notifier<IdCopyDraft?> {
  /// Copy pages made again after a side changed, one at a time.
  Future<void> _remaking = Future.value();

  /// The sides the copy page was last made from, so a change that leaves
  /// them as they were does not make it again.
  List<ScanPage?>? _madeFrom;

  @override
  IdCopyDraft? build() {
    ref.listen(scanControllerProvider, _sidesMayHaveChanged);
    return ref.watch(scanControllerProvider.select((s) => s.info?.idCopy));
  }

  ScanController get _scan => ref.read(scanControllerProvider.notifier);

  void start(IdCopyType type) {
    _madeFrom = null;
    _set(IdCopyDraft(type: type));
  }

  void update(IdCopyDraft Function(IdCopyDraft draft) change) {
    final draft = state;
    if (draft != null) _set(change(draft));
  }

  void _set(IdCopyDraft draft) {
    _scan.setIdCopy(draft);
    state = draft;
  }

  /// When a side of a finished copy changes (retaken, cropped, filtered,
  /// masked), anywhere in the app, the copy page is made again from the
  /// sides as they are now, so it never shows an old picture.
  void _sidesMayHaveChanged(ScanState? before, ScanState after) {
    final draft = after.info?.idCopy;
    // Only changes within one document: opening another one is not an edit.
    if (before == null || draft == null || draft.compositeId == null) return;
    if (before.info?.createdAt != after.info?.createdAt || before.info?.idCopy == null) return;
    final was = sidePages(before.info!.idCopy!, before);
    final now = sidePages(draft, after);
    if (listEquals(was, now) || now.any((s) => s == null)) return;
    _remaking = _remaking.then((_) => _remakeCopy()).catchError((Object e) => debugPrint('ID copy remake failed: $e'));
  }

  Future<void> _remakeCopy() async {
    final draft = ref.read(scanControllerProvider).info?.idCopy;
    final scan = ref.read(scanControllerProvider);
    final copyId = draft?.compositeId;
    if (draft == null || copyId == null || scan.pageById(copyId) == null) return;
    final sides = sidePages(draft, scan);
    if (sides.any((s) => s == null) || listEquals(sides, _madeFrom)) return;
    final jpeg = await _compose(
      paper: draft.paper,
      slots: idCopySlots(draft.type, paper: draft.paper, scale: draft.scale),
      pages: [for (final s in sides) s!],
      watermark: draft.watermark,
    );
    if (!ref.mounted) return;
    final page = await _scan.replaceMadePage(copyId, await _tempFile(jpeg));
    if (page != null) _madeFrom = sides;
  }

  /// Completes once every copy page being made again is in the draft.
  Future<void> get remade => _remaking;

  /// Makes the ID copy page from the sides and puts it first in the draft, in
  /// place of an earlier copy if there is one. The sides stay in the draft
  /// after it, as they are (US-ID-01.8: export never removes the sides).
  Future<ScanPage> makeCopyPage() async {
    await _remaking;
    final draft = state;
    if (draft == null) throw StateError('No ID copy is being made');
    final sides = sidePages(draft, ref.read(scanControllerProvider));
    if (sides.any((s) => s == null)) throw StateError('Capture every side first');
    final jpeg = await _compose(
      paper: draft.paper,
      slots: idCopySlots(draft.type, paper: draft.paper, scale: draft.scale),
      pages: [for (final s in sides) s!],
      watermark: draft.watermark,
    );
    final page = await _scan.addMadePage(await _tempFile(jpeg), at: 0, replacing: draft.compositeId);
    update((d) => d.withComposite(page.id));
    _madeFrom = sides;
    return page;
  }

  /// Puts [pages] together on one sheet (1 to [maxCollagePictures]) and adds
  /// it as a new page at the end of the draft.
  Future<ScanPage> makeCollagePage(List<ScanPage> pages, {PdfPageSize paper = PdfPageSize.a4}) async {
    final jpeg = await _compose(
      paper: paper,
      slots: collageSlots(pages.length, paper: paper),
      pages: pages,
    );
    return ref.read(scanControllerProvider.notifier).addMadePage(await _tempFile(jpeg));
  }

  Future<Uint8List> _compose({
    required PdfPageSize paper,
    required List<Rect> slots,
    required List<ScanPage> pages,
    String? watermark,
  }) async {
    final maker = ref.read(sideImageMakerProvider);
    final images = [for (final page in pages) await maker(page)];
    return ref.read(pageComposerProvider)(
      paperMm: paperSizeMm(paper),
      slots: slots,
      imagePaths: images,
      watermark: watermark,
    );
  }

  Future<String> _tempFile(Uint8List jpeg) async {
    final store = ref.read(pageStoreProvider);
    final dir = await store.renderDir;
    final file = File(p.join(dir.path, 'made_${store.newId()}.jpg'));
    await file.writeAsBytes(jpeg, flush: true);
    return file.path;
  }

  /// Saves the draft's pages as a PDF in the Library, filed as an ID card,
  /// under the document's name; saving again replaces that file and keeps
  /// its Library entry. With [only], just those pages go in, under the name
  /// with " copy" added. Pages are 200 dpi, so the copy prints at real size.
  Future<File> savePdf({List<ScanPage>? only}) async {
    final scan = ref.read(scanControllerProvider);
    final pages = only ?? scan.pages;
    final name = scan.info?.name ?? 'ID card';
    final file = await ref
        .read(pdfExporterProvider)
        .export(
          pages,
          ExportOptions(
            pageSize: PdfPageSize.fitImage,
            fitImageDpi: composeDpi,
            quality: ExportQuality.high,
            fileName: PdfEditSaver.safeFileName(only == null ? name : '$name copy'),
            // Basic exports carry the "Scanned with" mark, ID copies too.
            watermark: ref.read(planIncludesProvider(PlanFeature.noWatermark)) ? null : exportWatermark,
          ),
        );
    await ref.read(libraryProvider.notifier).addScan(file, pages, type: ScanType.idCard);
    if (only == null) ref.read(scanControllerProvider.notifier).markExported();
    return file;
  }
}

/// The picture of one side as it goes on the copy: cropped, filtered and
/// with its masks burned in, so a hidden number never reaches the page.
typedef SideImageMaker = Future<String> Function(ScanPage page);

final sideImageMakerProvider = Provider<SideImageMaker>(
  (ref) =>
      (page) async => (await ref.read(renderServiceProvider).renderMasked(page)).path,
);

/// Lays out pictures on a sheet of paper (see [composePage]). Tests swap in
/// one that does not need the GPU.
typedef PageComposer = Future<Uint8List> Function({
  required Size paperMm,
  required List<Rect> slots,
  required List<String> imagePaths,
  String? watermark,
});

final pageComposerProvider = Provider<PageComposer>(
  (ref) =>
      ({required paperMm, required slots, required imagePaths, watermark}) =>
          composePage(paperMm: paperMm, slots: slots, imagePaths: imagePaths, watermark: watermark),
);

/// The draft page of each side, in side order, or null for a side whose
/// page is no longer in the draft.
List<ScanPage?> sidePages(IdCopyDraft draft, ScanState scan) => [
  for (var i = 0; i < draft.type.sides; i++) i < draft.sideIds.length ? scan.pageById(draft.sideIds[i]) : null,
];
