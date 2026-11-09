import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cunning_scanner_service.dart';
import '../data/library_store.dart';
import '../data/mlkit_vision.dart';
import '../data/routed_ocr_engine.dart';
import '../data/platform_launch_actions.dart';
import '../data/smart_namer.dart';
import '../data/document_text_reader.dart';
import '../data/document_text_store.dart';
import '../data/export_state_store.dart';
import '../data/tesseract_ocr.dart';
import '../data/page_store.dart';
import '../data/photo_import_services.dart';
import '../data/plugin_batch_camera.dart';
import '../data/share_inbox_store.dart';
import '../debug/image_profiler.dart';
import '../domain/launch_action.dart';
import '../domain/models.dart';
import '../domain/ocr.dart';
import '../domain/photo_import.dart';
import '../domain/plan.dart';
import '../domain/qr_reader.dart';
import '../domain/scanner_service.dart';
import '../domain/share_inbox.dart';
import '../export/jpg_exporter.dart';
import '../export/pdf_exporter.dart';
import '../export/text_pdf_service.dart';
import '../export/word/pdf_text_reader.dart';
import '../export/word/word_service.dart';
import '../pdf_edit/pdf_edit_controller.dart';
import '../features/batch_capture/batch_camera.dart';
import '../imaging/corner_worker.dart';
import '../imaging/page_renderer.dart';
import '../imaging/render_queue.dart';
import '../imaging/render_service.dart';
import 'device_load.dart';
import 'preferences.dart';

// Services are plain providers so tests can override them (LLD Riverpod
// conventions).
final pageStoreProvider = Provider<PageStore>((ref) => PageStore());

final scannerServiceProvider = Provider<ScannerService>((ref) => CunningScannerService());

/// Limits how many page pictures render at once. Debug builds lower it to
/// act like a slower phone (lib/debug/phone_simulation.dart).
final renderQueueProvider = Provider<RenderQueue>((ref) => RenderQueue());

final renderServiceProvider = Provider<RenderService>(
  (ref) => RenderService(
    ref.watch(pageStoreProvider),
    queue: ref.watch(renderQueueProvider),
    profiler: ref.watch(imageProfilerProvider),
  ),
);

final pdfExporterProvider = Provider<PdfExporter>((ref) => PdfExporter(ref.watch(pageStoreProvider)));

final jpgExporterProvider = Provider<JpgExporter>((ref) => JpgExporter(ref.watch(pageStoreProvider)));

/// Makes text PDFs: OCR on the pages, then a PDF of the text with the
/// pictures kept (Pro and Gold).
final textPdfServiceProvider = Provider<TextPdfService>(
  (ref) => TextPdfService(
    ref.watch(pageStoreProvider),
    ref.watch(ocrEngineProvider),
    ref.watch(pdfRasterizerProvider),
    ref.watch(ocrPageImageProvider),
  ),
);

/// Converts saved PDFs to Word files and Word files to PDFs.
final wordServiceProvider = Provider<WordService>(
  (ref) =>
      WordService(ref.watch(pageStoreProvider), ref.watch(pdfRasterizerProvider), ref.watch(pdfTextReaderProvider)),
);

/// Reads the text layer of a PDF for Word conversion.
final pdfTextReaderProvider = Provider<PdfTextReader>((ref) => PdfrxTextReader());

final libraryStoreProvider = Provider<LibraryStore>((ref) => LibraryStore(ref.watch(pageStoreProvider)));

/// What was exported from each scan (SQLite), so unchanged scans reuse
/// their saved file.
final exportStateStoreProvider = Provider<ExportStateStore>(
  (ref) => SqliteExportStateStore(ref.watch(pageStoreProvider)),
);

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore(ref.watch(pageStoreProvider)));

final photoPickerProvider = Provider<PhotoPicker>((ref) => FilePickerPhotoPicker());

/// Images shared into the app from the gallery's share sheet.
final shareInboxProvider = Provider<ShareInbox>((ref) => DirectoryShareInbox(platformShareInboxDir));

/// Finds the page in a photo, for every kind of scan: the corner model
/// first on every plan, the hand-made detector when the model is not sure
/// (the smarter one on Pro and Gold).
final photoAnalyzerProvider = Provider<PhotoAnalyzer>((ref) {
  final smart = ref.watch(planIncludesProvider(PlanFeature.smartScan));
  return DetectorPhotoAnalyzer(smart: smart, worker: ref.watch(cornerWorkerProvider));
});

/// Longest side of the page image that text recognition reads.
const ocrImageSize = 2400;

/// The page as text recognition reads it: its crop, filter and masks, from
/// the render cache. The text PDF and the Word file reuse the same image, so
/// the text sits exactly where it was read and no page is drawn twice.
final ocrPageImageProvider = Provider<Future<RenderedImage> Function(ScanPage page)>((ref) {
  final render = ref.watch(renderServiceProvider);
  return (page) => render.renderMasked(page, maxDimension: ocrImageSize);
});

/// On-device text recognition. It reads each page as rendered with its crop
/// and filter, at a size that keeps small print legible, with its masks
/// burned in so hidden ID numbers are never read into the text: ML Kit for
/// Latin and Devanagari, Tesseract for the other Indian scripts.
final ocrEngineProvider = Provider<OcrEngine>((ref) {
  final pageImage = ref.watch(ocrPageImageProvider);
  Future<String> imageFor(ScanPage page) async => (await pageImage(page)).path;
  return RoutedOcrEngine(
    fallback: MlKitOcrEngine(imageFor: imageFor),
    special: TesseractOcrEngine(imageFor: imageFor),
    handles: TesseractOcrEngine.handles,
  );
});

/// App icon shortcuts and the home-screen widget.
final launchActionSourceProvider = Provider<LaunchActionSource>((ref) => PlatformLaunchActions());

/// Text of saved documents for Library search (Pro).
final documentTextStoreProvider = Provider<DocumentTextStore>((ref) => DocumentTextStore(ref.watch(pageStoreProvider)));

final documentTextReaderProvider = Provider<DocumentTextReader>(
  (ref) => DocumentTextReader(
    ref.watch(pdfTextReaderProvider),
    ref.watch(pdfRasterizerProvider),
    ref.watch(ocrEngineProvider),
  ),
);

/// Auto file naming (Pro): a name suggested from the first page's text.
final smartNamerProvider = Provider<SmartNamer>((ref) => SmartNamer(ref.watch(ocrEngineProvider)));

/// On-device QR reading for the camera's QR mode.
final qrReaderProvider = Provider<QrReader>((ref) {
  final reader = MlKitQrReader();
  ref.onDispose(reader.close);
  return reader;
});

/// Makes the live camera for Batch capture, one per visit to the screen.
/// How busy the phone is, for background work the camera can skip.
///
/// Debug builds that act as another phone (debug panel, "Simulate phone")
/// see that phone's memory and cores instead.
final deviceLoadProbeProvider = Provider<DeviceLoadProbe>((ref) {
  final real = PlatformDeviceLoadProbe();
  final phone = kDebugMode ? ref.watch(appSettingsProvider.select((s) => s.debugPhone)) : null;
  return phone == null ? real : SimulatedDeviceLoadProbe(real, phone);
});

final batchCameraProvider = Provider<BatchCameraFactory>((ref) => PluginBatchCamera.new);
