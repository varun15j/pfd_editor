import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/page_store.dart';
import '../../domain/ocr.dart';
import '../../domain/plan.dart';
import '../../domain/scanner_service.dart';
import '../../domain/table_extractor.dart';
import '../../export/xlsx_writer.dart';
import '../../ui/upgrade_dialog.dart';
import '../pages/scan_actions.dart';
import '../share/pdf_sharer.dart';

/// Tools > Table to Excel: one photo of a table, read on the device, checked
/// on screen and saved as an Excel (.xlsx) file. Gold only. Nothing leaves
/// the phone, so there is no cost per use and no usage cap.
///
/// [source] skips the question of camera or photo, when it is already known.
Future<void> scanTableToExcel(BuildContext context, WidgetRef ref, {ScanSource? source}) async {
  if (!await ensurePlan(context, ref, PlanFeature.tableToExcel, what: 'Table to Excel') || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final engine = ref.read(ocrEngineProvider);
  final capability = await engine.capability('en');
  if (engine is! OcrFileLayoutEngine || capability.readiness == OcrReadiness.unavailable) {
    say(capability.reason ?? 'Tables cannot be read on this device.');
    return;
  }
  if (!context.mounted) return;
  final from = source ?? await _askSource(context);
  if (from == null || !context.mounted) return;

  final scanner = ref.read(scannerServiceProvider);
  final String photo;
  try {
    final paths = await scanner.scan(source: from, maxPages: 1);
    if (paths.isEmpty) return;
    photo = paths.first;
  } on ScannerPermissionDenied catch (e) {
    if (!context.mounted) return;
    final choice = await showCameraPermissionGuide(context, permanently: e.permanently);
    if (!context.mounted) return;
    switch (choice) {
      case CameraGuideChoice.retry:
        return scanTableToExcel(context, ref, source: ScanSource.camera);
      case CameraGuideChoice.importPhotos:
        return scanTableToExcel(context, ref, source: ScanSource.gallery);
      case CameraGuideChoice.settings:
        await openAppSettings();
      case null:
    }
    return;
  } on ScannerFailure catch (e) {
    say('Could not take the photo. ${e.message}');
    return;
  }
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: Space.lg),
              Expanded(child: Text('Reading the table')),
            ],
          ),
        ),
      ),
    ),
  );
  ExtractedTable table;
  String? keptPhoto;
  try {
    final layout = await (engine as OcrFileLayoutEngine).recognizeLayoutFile(photo);
    table = const TableExtractor().extract(layout);
    // The scanner's file is temporary; keep a copy to show next to the table.
    keptPhoto = p.join(Directory.systemTemp.path, 'lumascan_table_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await File(photo).copy(keptPhoto);
  } on Object {
    navigator.pop();
    say('Could not read the photo. Try again with the table filling the frame.');
    return;
  } finally {
    unawaited(scanner.cleanUp());
  }
  navigator.pop();
  if (!context.mounted) return;
  if (table.isEmpty) {
    say('No text found in the photo. Try again with the table filling the frame and in focus.');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TablePreviewScreen(table: table, photoPath: keptPhoto),
    ),
  );
}

Future<ScanSource?> _askSource(BuildContext context) => showModalBottomSheet<ScanSource>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
            child: Text('Table to Excel', style: Theme.of(sheetContext).textTheme.headlineSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              'Fill the frame with the table, straight on and in good light. It is read on this phone.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ScanSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.pop(sheetContext, ScanSource.gallery),
          ),
        ],
      ),
    ),
  ),
);

/// The table as it was read, to check before saving. Tapping a cell fixes
/// its text; Save writes the Excel file.
class TablePreviewScreen extends ConsumerStatefulWidget {
  const TablePreviewScreen({super.key, required this.table, this.photoPath});

  final ExtractedTable table;

  /// The photo the table came from, shown on request to compare.
  final String? photoPath;

  @override
  ConsumerState<TablePreviewScreen> createState() => _TablePreviewScreenState();
}

class _TablePreviewScreenState extends ConsumerState<TablePreviewScreen> {
  late ExtractedTable _table = widget.table;
  bool _saving = false;

  @override
  void dispose() {
    final photo = widget.photoPath;
    if (photo != null) {
      try {
        File(photo).deleteSync();
      } on FileSystemException {
        // A temp file; the system clears it in time.
      }
    }
    super.dispose();
  }

  Future<void> _edit(int row, int column) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CellEditor(title: 'Cell ${XlsxWriter.columnName(column)}${row + 1}', text: _table.rows[row][column]),
    );
    if (text != null && mounted) setState(() => _table = _table.withCell(row, column, text.trim()));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await saveTableAsExcel(ref.read(pageStoreProvider), _table, name: tableFileName(DateTime.now()));
      if (!mounted) return;
      await showExcelSavedSheet(context, file);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the Excel file. $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showPhoto() => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: InteractiveViewer(maxScale: 5, child: Image.file(File(widget.photoPath!)))),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    final rows = _table.rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check the table'),
        actions: [
          if (widget.photoPath != null)
            IconButton(tooltip: 'Show the photo', icon: const Icon(Icons.image_outlined), onPressed: _showPhoto),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.md),
            child: Text(
              '${_table.rowCount} ${_table.rowCount == 1 ? 'row' : 'rows'}, '
              '${_table.columnCount} ${_table.columnCount == 1 ? 'column' : 'columns'}. '
              'Tap a cell to fix it. Check numbers before you rely on them.',
              style: text.bodyMedium,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder.all(color: c.line),
                  children: [
                    for (var r = 0; r < rows.length; r++)
                      TableRow(
                        decoration: r == 0 ? BoxDecoration(color: c.surfaceRaised) : null,
                        children: [
                          for (var col = 0; col < rows[r].length; col++)
                            InkWell(
                              onTap: () => _edit(r, col),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minWidth: 56, maxWidth: 220, minHeight: 40),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
                                  child: Text(
                                    rows[r][col],
                                    style: r == 0
                                        ? text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
                                        : text.bodyMedium,
                                    textAlign: XlsxWriter.numberIn(rows[r][col]) != null
                                        ? TextAlign.end
                                        : TextAlign.start,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.md),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.table_chart_outlined),
                label: Text(_saving ? 'Saving' : 'Save as Excel'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixes the text of one cell. It owns its text controller, so the
/// controller lives as long as the dialog, closing animation included.
class _CellEditor extends StatefulWidget {
  const _CellEditor({required this.title, required this.text});

  final String title;
  final String text;

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(controller: _controller, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Done')),
    ],
  );
}

/// "Table 2026-10-27 1415.xlsx".
String tableFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Table ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}.xlsx';
}

/// Writes [table] to the exports folder as [name], or "name (2).xlsx" when
/// that file exists. The Library holds PDFs, so the file is not added there.
Future<File> saveTableAsExcel(PageStore store, ExtractedTable table, {required String name}) async =>
    store.writeExportAtomically(await store.freeExportName(name), XlsxWriter.write(table.rows));

/// Hands an Excel file to the system share sheet. Behind an interface so
/// tests do not need the plugin.
abstract class XlsxSharer {
  /// Throws when the share sheet cannot be opened.
  Future<SendOutcome> send(String path, {Rect? origin});
}

class SharePlusXlsxSharer implements XlsxSharer {
  @override
  Future<SendOutcome> send(String path, {Rect? origin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: XlsxWriter.mimeType)],
        sharePositionOrigin: origin,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? SendOutcome.dismissed : SendOutcome.sent;
  }
}

final xlsxSharerProvider = Provider<XlsxSharer>((ref) => SharePlusXlsxSharer());

/// Asks what to do with the Excel file once it is saved: open it, share it,
/// or save it to the Documents folder.
Future<void> showExcelSavedSheet(BuildContext context, File file) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ExcelSavedSheet(file: file),
);

class ExcelSavedSheet extends ConsumerWidget {
  const ExcelSavedSheet({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Excel file saved', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(p.basename(file.path), style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open in Excel'),
              onTap: () => _open(context),
            ),
            Builder(
              builder: (tileContext) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.ios_share),
                title: const Text('Share'),
                onTap: () => _share(context, ref, tileContext),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Save to Documents folder'),
              subtitle: const Text('Choose Documents in the save dialog'),
              onTap: () => _saveToDocuments(context),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await OpenFilex.open(file.path, type: XlsxWriter.mimeType);
    if (result.type == ResultType.done) {
      navigator.pop();
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.type) {
          ResultType.noAppToOpen => 'No app on this device can open Excel files. Try Share instead.',
          ResultType.fileNotFound => 'This Excel file is no longer on this device.',
          _ => 'Could not open the Excel file. ${result.message}',
        }),
      ),
    );
  }

  /// Shares from the tile that was tapped, so the iPad share sheet has
  /// somewhere to point.
  Future<void> _share(BuildContext context, WidgetRef ref, BuildContext tileContext) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final outcome = await ref.read(xlsxSharerProvider).send(file.path, origin: origin);
      if (outcome == SendOutcome.sent) navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the share sheet. $e')));
    }
  }

  Future<void> _saveToDocuments(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save Excel file to Documents',
        fileName: p.basename(file.path),
        bytes: await file.readAsBytes(),
        mimeType: XlsxWriter.mimeType,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      // Cancelling the dialog keeps the sheet open, so another option can be picked.
      if (saved == null) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved to Documents')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the Excel file. $e')));
    }
  }
}
