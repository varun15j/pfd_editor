import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cunning_scanner_service.dart';
import '../data/library_store.dart';
import '../data/mlkit_vision.dart';
import '../data/page_store.dart';
import '../data/photo_import_services.dart';
import '../data/plugin_batch_camera.dart';
import '../debug/image_profiler.dart';
import '../domain/ocr.dart';
import '../domain/photo_import.dart';
import '../domain/qr_reader.dart';
import '../domain/scanner_service.dart';
import '../export/pdf_exporter.dart';
import '../export/text_pdf_service.dart';
import '../pdf_edit/pdf_edit_controller.dart';
import '../features/batch_capture/batch_camera.dart';
import '../imaging/render_service.dart';

// Services are plain providers so tests can override them (LLD Riverpod
// conventions).
final pageStoreProvider = Provider<PageStore>((ref) => PageStore());

final scannerServiceProvider = Provider<ScannerService>((ref) => CunningScannerService());

final renderServiceProvider = Provider<RenderService>(
  (ref) => RenderService(ref.watch(pageStoreProvider), profiler: ref.watch(imageProfilerProvider)),
);

final pdfExporterProvider = Provider<PdfExporter>((ref) => PdfExporter(ref.watch(pageStoreProvider)));

/// Makes text PDFs: OCR on the pages, then a PDF of the text with the
/// pictures kept (Pro and Gold).
final textPdfServiceProvider = Provider<TextPdfService>(
  (ref) => TextPdfService(ref.watch(pageStoreProvider), ref.watch(ocrEngineProvider), ref.watch(pdfRasterizerProvider)),
);

final libraryStoreProvider = Provider<LibraryStore>((ref) => LibraryStore(ref.watch(pageStoreProvider)));

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore(ref.watch(pageStoreProvider)));

final photoPickerProvider = Provider<PhotoPicker>((ref) => FilePickerPhotoPicker());

final photoAnalyzerProvider = Provider<PhotoAnalyzer>((ref) => DetectorPhotoAnalyzer());

/// On-device text recognition. It reads each page as rendered with its crop
/// and filter, at a size that keeps small print legible.
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => MlKitOcrEngine(
    imageFor: (page) async => (await ref.read(renderServiceProvider).render(page, maxDimension: 2400)).path,
  ),
);

/// On-device QR reading for the camera's QR mode.
final qrReaderProvider = Provider<QrReader>((ref) {
  final reader = MlKitQrReader();
  ref.onDispose(reader.close);
  return reader;
});

/// Makes the live camera for Batch capture, one per visit to the screen.
final batchCameraProvider = Provider<BatchCameraFactory>((ref) => PluginBatchCamera.new);
