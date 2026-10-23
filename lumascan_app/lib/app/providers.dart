import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cunning_scanner_service.dart';
import '../data/library_store.dart';
import '../data/mlkit_vision.dart';
import '../data/routed_ocr_engine.dart';
import '../data/tesseract_ocr.dart';
import '../data/page_store.dart';
import '../data/photo_import_services.dart';
import '../data/plugin_batch_camera.dart';
import '../debug/image_profiler.dart';
import '../domain/models.dart';
import '../domain/ocr.dart';
import '../domain/photo_import.dart';
import '../domain/plan.dart';
import '../domain/qr_reader.dart';
import '../domain/scanner_service.dart';
import '../export/jpg_exporter.dart';
import '../export/pdf_exporter.dart';
import '../export/text_pdf_service.dart';
import '../export/word/pdf_text_reader.dart';
import '../export/word/word_service.dart';
import '../pdf_edit/pdf_edit_controller.dart';
import '../features/batch_capture/batch_camera.dart';
import '../imaging/render_service.dart';
import 'device_load.dart';
import 'preferences.dart';

// Services are plain providers so tests can override them (LLD Riverpod
// conventions).
final pageStoreProvider = Provider<PageStore>((ref) => PageStore());

final scannerServiceProvider = Provider<ScannerService>((ref) => CunningScannerService());

final renderServiceProvider = Provider<RenderService>(
  (ref) => RenderService(ref.watch(pageStoreProvider), profiler: ref.watch(imageProfilerProvider)),
);

final pdfExporterProvider = Provider<PdfExporter>((ref) => PdfExporter(ref.watch(pageStoreProvider)));

final jpgExporterProvider = Provider<JpgExporter>((ref) => JpgExporter(ref.watch(pageStoreProvider)));

/// Makes text PDFs: OCR on the pages, then a PDF of the text with the
/// pictures kept (Pro and Gold).
final textPdfServiceProvider = Provider<TextPdfService>(
  (ref) => TextPdfService(ref.watch(pageStoreProvider), ref.watch(ocrEngineProvider), ref.watch(pdfRasterizerProvider)),
);

/// Converts saved PDFs to Word files and Word files to PDFs.
final wordServiceProvider = Provider<WordService>(
  (ref) =>
      WordService(ref.watch(pageStoreProvider), ref.watch(pdfRasterizerProvider), ref.watch(pdfTextReaderProvider)),
);

/// Reads the text layer of a PDF for Word conversion.
final pdfTextReaderProvider = Provider<PdfTextReader>((ref) => PdfrxTextReader());

final libraryStoreProvider = Provider<LibraryStore>((ref) => LibraryStore(ref.watch(pageStoreProvider)));

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore(ref.watch(pageStoreProvider)));

final photoPickerProvider = Provider<PhotoPicker>((ref) => FilePickerPhotoPicker());

final photoAnalyzerProvider = Provider<PhotoAnalyzer>(
  (ref) => DetectorPhotoAnalyzer(smart: ref.watch(planIncludesProvider(PlanFeature.smartScan))),
);

/// On-device text recognition. It reads each page as rendered with its crop
/// and filter, at a size that keeps small print legible: ML Kit for Latin and
/// Devanagari, Tesseract for the other Indian scripts.
final ocrEngineProvider = Provider<OcrEngine>((ref) {
  Future<String> imageFor(ScanPage page) async =>
      (await ref.read(renderServiceProvider).render(page, maxDimension: 2400)).path;
  return RoutedOcrEngine(
    fallback: MlKitOcrEngine(imageFor: imageFor),
    special: TesseractOcrEngine(imageFor: imageFor),
    handles: TesseractOcrEngine.handles,
  );
});

/// On-device QR reading for the camera's QR mode.
final qrReaderProvider = Provider<QrReader>((ref) {
  final reader = MlKitQrReader();
  ref.onDispose(reader.close);
  return reader;
});

/// Makes the live camera for Batch capture, one per visit to the screen.
/// How busy the phone is, for background work the camera can skip.
final deviceLoadProbeProvider = Provider<DeviceLoadProbe>((ref) => PlatformDeviceLoadProbe());

final batchCameraProvider = Provider<BatchCameraFactory>((ref) => PluginBatchCamera.new);
