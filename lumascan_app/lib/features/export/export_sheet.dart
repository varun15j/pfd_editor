import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../app/credits.dart';
import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../domain/credits.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../domain/saved_export.dart';
import '../../export/pdf_exporter.dart';
import '../../pdf_edit/pdf_saver.dart';
import '../../export/text_pdf_service.dart';
import '../../ui/file_size.dart';
import '../../ui/upgrade_dialog.dart';
import '../library/library_controller.dart';
import '../pages/scan_controller.dart';
import '../cloud/drive_sync.dart';
import '../credits/credits_screen.dart';
import '../share/send_pdf_sheet.dart';
import 'saved_exports.dart';
import '../../ui/luma_icons.dart';

export '../../ui/file_size.dart';

Future<void> showExportSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // Dragging down would close the sheet mid-save; back and the scrim are
  // blocked by the sheet itself while saving.
  enableDrag: false,
  builder: (_) => const ExportSheet(),
);

/// Save (S09): name, page size and quality with estimated sizes, progress,
/// then share. Success is shown only once the file is on disk.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  late final TextEditingController _name;
  PdfPageSize _size = PdfPageSize.a4;
  ExportQuality _quality = ExportQuality.medium;

  /// Export a text PDF (Pro and Gold): OCR reads the pages and the PDF holds
  /// their text, with pictures kept as images.
  bool _textPdf = false;

  /// "2 / 5" at the foot of each page (Pro and Gold).
  bool _pageNumbers = false;
  double? _progress;
  File? _result;
  String? _error;
  bool _inLibrary = false;

  /// Nothing changed since the last export, so its file was reused.
  bool _reused = false;
  bool _originalsRemoved = false;

  /// Page count of the saved PDF; the draft may be emptied right after saving.
  int _savedPages = 0;

  /// The name the sheet opened with. A suggested name replaces it only
  /// while the user has not typed their own.
  late final String _openingName;

  /// True while the first page is read for a name (Auto file naming).
  bool _naming = false;

  /// Said under the name when a suggestion found nothing to go on.
  String? _namingNote;

  bool get _saving => _progress != null && _result == null;

  @override
  void initState() {
    super.initState();
    // The scan's own name, such as "2026-10-11 Scan"; the pattern from
    // Settings only for pages that have none.
    final scanName = ref.read(scanControllerProvider).info?.name;
    _name = TextEditingController(
      text: scanName ?? ref.read(appSettingsProvider).fileNamePattern.format(DateTime.now()),
    )..addListener(_onNameChanged);
    _openingName = _name.text;
    // Pro and Gold: offer a name from the page text straight away.
    if (ref.read(planIncludesProvider(PlanFeature.smartName))) _suggestName(auto: true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _nameValid => _name.text.trim().isNotEmpty;

  Future<void> _export() async {
    // A second tap before the sheet rebuilds must not start a second save.
    if (_saving || !_nameValid) return;
    final pages = ref.read(scanControllerProvider).pages;
    // Read up front: the export finishes and is filed even if the sheet is
    // closed meanwhile.
    final library = ref.read(libraryProvider.notifier);
    final store = ref.read(pageStoreProvider);
    final exporter = ref.read(pdfExporterProvider);
    final textPdf = _textPdf && ref.read(planIncludesProvider(PlanFeature.textPdf));
    final textService = ref.read(textPdfServiceProvider);
    // Basic PDFs carry the "Scanned with" mark; Pro and Gold have none.
    final watermark = ref.read(planIncludesProvider(PlanFeature.noWatermark)) ? null : exportWatermark;
    final pageNumbers = _pageNumbers && ref.read(planIncludesProvider(PlanFeature.pageNumbers));
    final fileName = textPdf ? TextPdfService.textName(_name.text) : PdfEditSaver.safeFileName(_name.text);
    final draft = ref.read(scanControllerProvider.notifier);
    final keepOriginals = ref.read(appSettingsProvider).keepOriginals;
    final info = ref.read(scanControllerProvider).info;
    final savedExports = ref.read(savedExportsProvider.notifier);
    final sync = ref.read(driveSyncProvider.notifier);
    final keepLayout = ref.read(planIncludesProvider(PlanFeature.smartScan));
    final language = ref.read(ocrLanguageProvider);
    final format = textPdf ? ExportFormat.textPdf : ExportFormat.pdf;
    // Everything that changes the file; the same again reuses the saved one.
    final fingerprint = exportFingerprint(
      pages,
      fileName: fileName,
      options: textPdf
          ? {'keepLayout': keepLayout, 'language': language}
          : {'size': _size.name, 'quality': _quality.name, 'watermark': watermark, 'pageNumbers': pageNumbers},
    );
    final docKey = info == null ? null : scanDocKey(info);
    final credits = ref.read(creditsProvider.notifier);
    var charged = false;
    _savedPages = pages.length;
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final plan = docKey == null
          ? null
          : await savedExports.plan(docKey: docKey, format: format, fingerprint: fingerprint, fileName: fileName);
      if (plan is ExportReuse) {
        _savedPages = plan.saved.pageCount;
        if (mounted) {
          setState(() {
            _result = File(plan.saved.path);
            _reused = true;
            _inLibrary = true;
          });
        }
        draft.markExported();
        if (!keepOriginals) {
          await draft.clear();
          if (mounted) setState(() => _originalsRemoved = true);
        }
        return;
      }
      // A new file uses an export's credits; the same export again reuses
      // the saved file and is free. Given back if the export fails.
      if (!credits.trySpend(CreditAction.exporting, note: fileName)) {
        if (mounted) {
          setState(() => _progress = null);
          await showOutOfCreditsSheet(context, CreditAction.exporting);
        }
        return;
      }
      charged = true;
      final previous = plan is ExportNew ? plan.previous : null;
      // Exporting again replaces the scan's earlier file; a name another
      // file already has gets a number, never replaces it.
      final target = plan is ExportNew ? plan.fileName : await store.freeExportName(fileName);
      final File file;
      var savedPages = pages.length;
      if (textPdf) {
        final made = await textService.fromPages(
          pages,
          fileName: target,
          keepLayout: keepLayout,
          languageCode: language,
          onProgress: (f) {
            if (mounted) setState(() => _progress = f);
          },
        );
        file = made.file;
        savedPages = made.pageCount;
      } else {
        file = await exporter.export(
          pages,
          // A name that is already taken gets a number, never replaces a file.
          ExportOptions(
            pageSize: _size,
            quality: _quality,
            fileName: target,
            watermark: watermark,
            pageNumbers: pageNumbers,
          ),
          onProgress: (done, total) {
            if (mounted) setState(() => _progress = done / total);
          },
        );
      }
      _savedPages = savedPages;
      if (mounted) setState(() => _result = file);
      draft.markExported();
      // The PDF is already safe on disk; a failed index write only means it
      // is missing from the Library list, so it is reported, not thrown.
      final saved = await library.addScan(file, pages, pageCount: savedPages, replaceId: previous?.libraryId);
      if (mounted) setState(() => _inLibrary = true);
      if (docKey != null) {
        await savedExports.record(
          SavedExport(
            docKey: docKey,
            format: format,
            path: file.path,
            fingerprint: fingerprint,
            name: info!.name,
            pageCount: savedPages,
            sizeBytes: file.lengthSync(),
            exportedAt: DateTime.now(),
            libraryId: saved.id,
          ),
          previous: previous,
        );
      }
      // Settings > Sync: a copy goes to Google Drive (now, or once the phone
      // may sync). An unchanged export is already there.
      if (!_reused) unawaited(sync.enqueue(file));
      if (!keepOriginals) {
        // Settings: do not keep page images once the PDF is saved. Only after
        // the PDF is safely in the Library, so a failed save loses nothing.
        await draft.clear();
        if (mounted) setState(() => _originalsRemoved = true);
      }
    } on Object catch (e) {
      // No file was made: the credits come back.
      if (charged && _result == null) credits.refund(CreditAction.exporting, note: fileName);
      if (!mounted) return;
      if (_result != null) {
        setState(() => _error = 'The PDF was created but could not be added to your Library. ($e)');
      } else {
        setState(() {
          _progress = null;
          _error = 'Export failed. Your pages are unchanged. ($e)';
        });
      }
    }
  }

  /// Reads the first page and puts a name from its text in the field, such
  /// as "Invoice INV-2041 2026-10-26". When [auto], a name the user has
  /// typed meanwhile is kept and nothing is said if no name is found.
  Future<void> _suggestName({bool auto = false}) async {
    if (_naming) return;
    if (!auto && !await ensurePlan(context, ref, PlanFeature.smartName, what: 'Smart file names')) return;
    final pages = ref.read(scanControllerProvider).pages;
    final namer = ref.read(smartNamerProvider);
    final language = ref.read(ocrLanguageProvider);
    setState(() {
      _naming = true;
      _namingNote = null;
    });
    final name = await namer.suggest(pages, languageCode: language);
    if (!mounted) return;
    setState(() {
      _naming = false;
      if (name != null && (!auto || _name.text == _openingName)) {
        _name.text = name;
      } else if (name == null && !auto) {
        _namingNote = 'No title, number or date found on the first page.';
      }
    });
  }

  Future<void> _pickKind(bool textPdf) async {
    if (textPdf && !await ensurePlan(context, ref, PlanFeature.textPdf, what: 'Text PDF')) return;
    if (mounted) setState(() => _textPdf = textPdf);
  }

  Future<void> _setPageNumbers(bool on) async {
    if (on && !await ensurePlan(context, ref, PlanFeature.pageNumbers, what: 'Page numbers')) return;
    if (mounted) setState(() => _pageNumbers = on);
  }

  /// Saves a copy where the user picks in the system save screen: Google
  /// Drive (when its app is installed), Files, Downloads or another app.
  Future<void> _saveCopy() async {
    final file = _result!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save to Google Drive or Files',
        fileName: p.basename(file.path),
        bytes: await file.readAsBytes(),
        mimeType: 'application/pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (saved != null) messenger.showSnackBar(const SnackBar(content: Text('Copy saved')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save a copy. $e')));
    }
  }

  Future<void> _send() {
    final file = _result!;
    return showSendPdfSheet(context, pdfPath: file.path, name: p.basename(file.path), pageCount: _savedPages);
  }

  @override
  Widget build(BuildContext context) {
    final draftPages = ref.watch(scanControllerProvider.select((s) => s.pages.length));
    final pageCount = _result != null ? _savedPages : draftPages;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final saving = _saving;
    final hasTextPdf = ref.watch(planIncludesProvider(PlanFeature.textPdf));
    final hasPageNumbers = ref.watch(planIncludesProvider(PlanFeature.pageNumbers));
    final hasSmartName = ref.watch(planIncludesProvider(PlanFeature.smartName));
    final watermarked = !ref.watch(planIncludesProvider(PlanFeature.noWatermark));

    return PopScope(
      canPop: !saving,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 20, 22, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (result != null) ...[
                Text(
                  _reused ? 'No changes since your last export' : (_textPdf ? 'Text PDF saved' : 'PDF saved'),
                  style: textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${p.basename(result.path)} · $pageCount page${pageCount == 1 ? '' : 's'} · '
                  '${formatFileSize(result.lengthSync())}',
                ),
                if (_reused) ...[
                  const SizedBox(height: 4),
                  Text('Your saved file is used, so nothing was made again.', style: textTheme.bodySmall),
                ] else if (_inLibrary) ...[
                  const SizedBox(height: 4),
                  Text('Saved in the Saved folder. Exporting this scan again replaces it.', style: textTheme.bodySmall),
                ],
                if (_originalsRemoved) ...[
                  const SizedBox(height: 4),
                  Text(
                    'The page images were removed from this device, as set in Settings.',
                    style: textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 16),
                const _SyncLine(),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _send, icon: const Icon(LumaIcons.share), label: const Text('Share')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saveCopy,
                  icon: const Icon(LumaIcons.googleDrive),
                  label: const Text('Save to Google Drive or Files'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ] else ...[
                Text(_textPdf ? 'Save as text PDF' : 'Save as PDF', style: textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('$pageCount page${pageCount == 1 ? '' : 's'}', style: textTheme.bodySmall),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  enabled: !saving,
                  maxLength: 80,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'File name',
                    suffixText: _textPdf ? ' (text).pdf' : '.pdf',
                    border: const OutlineInputBorder(),
                    counterText: '',
                    errorText: _nameValid ? null : 'Enter a name for the PDF',
                    helperText: _naming ? 'Reading the page for a name…' : _namingNote,
                    suffixIcon: _naming
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            tooltip: hasSmartName ? 'Name from page text' : 'Name from page text · Pro',
                            icon: Icon(hasSmartName ? LumaIcons.smart : LumaIcons.proBadge),
                            onPressed: saving || pageCount == 0 ? null : _suggestName,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, icon: Icon(LumaIcons.pdf), label: Text('PDF')),
                    ButtonSegment(
                      value: true,
                      icon: Icon(hasTextPdf ? LumaIcons.textResult : LumaIcons.proBadge),
                      label: Text(hasTextPdf ? 'Text PDF' : 'Text PDF · Pro'),
                    ),
                  ],
                  selected: {_textPdf},
                  onSelectionChanged: saving ? null : (v) => _pickKind(v.first),
                ),
                const SizedBox(height: 16),
                if (_textPdf)
                  Text(
                    'Each page is read on this device and its text goes into the PDF. '
                    'Pictures and anything that could not be read stay as images. '
                    'This takes longer than a plain PDF.',
                    style: textTheme.bodySmall,
                  )
                else ...[
                  Text('Page size', style: textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<PdfPageSize>(
                    segments: [for (final s in PdfPageSize.values) ButtonSegment(value: s, label: Text(s.label))],
                    selected: {_size},
                    onSelectionChanged: saving ? null : (v) => setState(() => _size = v.first),
                  ),
                  const SizedBox(height: 16),
                  Text('Quality', style: textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final q in ExportQuality.values)
                    _QualityTile(
                      quality: q,
                      pageCount: pageCount,
                      selected: q == _quality,
                      onTap: saving ? null : () => setState(() => _quality = q),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    secondary: Icon(hasPageNumbers ? LumaIcons.pageNumbers : LumaIcons.proBadge),
                    title: Text(hasPageNumbers ? 'Page numbers' : 'Page numbers · Pro'),
                    subtitle: const Text('Adds "2 / 5" at the foot of each page'),
                    value: _pageNumbers && hasPageNumbers,
                    onChanged: saving ? null : _setPageNumbers,
                  ),
                  if (watermarked)
                    Text(
                      'Basic PDFs have a small "$exportWatermark" at the foot of each page. '
                      'Pro and Gold PDFs have none.',
                      style: textTheme.bodySmall,
                    ),
                ],
                const SizedBox(height: 16),
                if (saving) ...[
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    'Saving… ${((_progress ?? 0) * 100).round()}%',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: pageCount == 0 || saving || !_nameValid ? null : _export,
                  icon: const Icon(LumaIcons.pdf),
                  label: Text(saving ? 'Saving…' : (_textPdf ? 'Save text PDF' : 'Save PDF')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One quality choice with its estimated size for this document.
class _QualityTile extends StatelessWidget {
  const _QualityTile({required this.quality, required this.pageCount, required this.selected, required this.onTap});

  final ExportQuality quality;
  final int pageCount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = formatFileSize(PdfExporter.estimateBytes(pageCount, quality));
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        enabled: onTap != null,
        onTap: onTap,
        leading: Icon(selected ? LumaIcons.radioOn : LumaIcons.radioOff),
        title: Text(quality.label),
        subtitle: Text(quality.hint),
        trailing: Text('about $size'),
      ),
    );
  }
}

/// Under a saved export: where its Google Drive copy is, when sync is on.
class _SyncLine extends ConsumerWidget {
  const _SyncLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveSyncProvider).value;
    if (state == null || state.account == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final line = switch (state) {
      DriveSyncState(error: final String error) => error,
      DriveSyncState(uploading: true) => 'Uploading to Google Drive…',
      DriveSyncState(pending: 0) => 'Saved to Google Drive in the $appName folder.',
      DriveSyncState(hold: SyncHold.off) => 'Sync is off, so it waits on this phone.',
      DriveSyncState(hold: SyncHold.offline) => 'Will upload to Google Drive when you are online.',
      DriveSyncState(hold: SyncHold.waitingForWifi) => 'Will upload to Google Drive on Wi-Fi.',
      _ => 'Waiting to upload to Google Drive.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(LumaIcons.googleDrive, size: 16, color: textTheme.bodySmall?.color),
          const SizedBox(width: 6),
          Expanded(child: Text(line, style: textTheme.bodySmall)),
        ],
      ),
    );
  }
}
