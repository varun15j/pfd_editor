import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

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

/// The ID copy being made in ID card mode, or null outside it. Kept in
/// memory only: the pages themselves are in the scan draft, which is saved
/// as it changes, so nothing taken is lost if the app closes.
final idCopyDraftProvider = NotifierProvider<IdCopyDraftNotifier, IdCopyDraft?>(IdCopyDraftNotifier.new);

class IdCopyDraftNotifier extends Notifier<IdCopyDraft?> {
  @override
  IdCopyDraft? build() => null;

  void start(IdCopyType type) => state = IdCopyDraft(type: type);

  void update(IdCopyDraft Function(IdCopyDraft draft) change) {
    final draft = state;
    if (draft != null) state = change(draft);
  }

  /// Makes the ID copy page from the sides and puts it first in the draft, in
  /// place of an earlier copy if there is one. The sides stay in the draft
  /// after it, as they are (US-ID-01.8: export never removes the sides).
  Future<ScanPage> makeCopyPage() async {
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
    final page = await ref
        .read(scanControllerProvider.notifier)
        .addMadePage(await _tempFile(jpeg), at: 0, replacing: draft.compositeId);
    update((d) => d.withComposite(page.id));
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
