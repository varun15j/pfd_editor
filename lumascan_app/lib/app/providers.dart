import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cunning_scanner_service.dart';
import '../data/page_store.dart';
import '../domain/scanner_service.dart';
import '../export/pdf_exporter.dart';
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
