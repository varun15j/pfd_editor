import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cunning_scanner_service.dart';
import '../data/library_store.dart';
import '../data/page_store.dart';
import '../data/photo_import_services.dart';
import '../data/plugin_batch_camera.dart';
import '../domain/ocr.dart';
import '../domain/photo_import.dart';
import '../domain/scanner_service.dart';
import '../export/pdf_exporter.dart';
import '../features/batch_capture/batch_camera.dart';
import '../imaging/render_service.dart';

// Services are plain providers so tests can override them (LLD Riverpod
// conventions).
final pageStoreProvider = Provider<PageStore>((ref) => PageStore());

final scannerServiceProvider = Provider<ScannerService>((ref) => CunningScannerService());

final renderServiceProvider = Provider<RenderService>(
  (ref) => RenderService(ref.watch(pageStoreProvider)),
);

final pdfExporterProvider = Provider<PdfExporter>(
  (ref) => PdfExporter(ref.watch(pageStoreProvider)),
);

final libraryStoreProvider = Provider<LibraryStore>((ref) => LibraryStore(ref.watch(pageStoreProvider)));

final draftStoreProvider = Provider<DraftStore>((ref) => DraftStore(ref.watch(pageStoreProvider)));

final photoPickerProvider = Provider<PhotoPicker>((ref) => FilePickerPhotoPicker());

final photoAnalyzerProvider = Provider<PhotoAnalyzer>((ref) => DetectorPhotoAnalyzer());

final ocrEngineProvider = Provider<OcrEngine>((ref) => const UnavailableOcrEngine());

/// Makes the live camera for Batch capture, one per visit to the screen.
final batchCameraProvider = Provider<BatchCameraFactory>((ref) => PluginBatchCamera.new);
