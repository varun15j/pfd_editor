import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/ocr.dart';
import '../../domain/plan.dart';
import '../../ui/upgrade_dialog.dart';
import '../../export/ocr_pdf_builder.dart';
import '../share/pdf_sharer.dart';
import '../pages/scan_controller.dart';
import 'batch_ocr_job.dart';

/// Batch OCR (BE-07): checks that text recognition can run, then reads the
/// selected pages one by one with progress and Cancel, and ends with which
/// pages had text, had none, or failed (with Retry). Pages stay usable as
/// images whatever happens here.
class BatchOcrScreen extends ConsumerStatefulWidget {
  const BatchOcrScreen({super.key, required this.pageIds, this.languageCode = 'en'});

  final List<String> pageIds;
  final String languageCode;

  @override
  ConsumerState<BatchOcrScreen> createState() => _BatchOcrScreenState();
}

class _BatchOcrScreenState extends ConsumerState<BatchOcrScreen> {
  late final OcrEngine _engine = ref.read(ocrEngineProvider);
  late Future<OcrCapability> _capability = _engine.capability(widget.languageCode);
  BatchOcrJob? _job;
  bool _preparing = false;

  @override
  void dispose() {
    _job?.cancel();
    _job?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() => _preparing = true);
    try {
      await _engine.prepare(widget.languageCode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed. Try again.')));
      }
    }
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _capability = _engine.capability(widget.languageCode);
    });
  }

  bool _building = false;

  /// Builds a text PDF of the pages that were read, then offers it to share.
  Future<void> _createPdf(BatchOcrJob job, int? Function(String) numberOf) async {
    if (!await ensurePlan(context, ref, PlanFeature.textPdf, what: 'Text PDF') || !mounted) return;
    final state = ref.read(scanControllerProvider);
    final pages = <OcrPdfPage>[
      for (final r in job.results)
        if ((r.status == OcrPageStatus.done || r.status == OcrPageStatus.empty) && state.pageById(r.pageId) != null)
          OcrPdfPage(
            page: state.pageById(r.pageId)!,
            number: numberOf(r.pageId) ?? 0,
            text: r.text ?? '',
            layout: r.layout,
          ),
    ];
    if (pages.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _building = true);
    try {
      final file = (await OcrPdfBuilder(ref.read(pageStoreProvider)).build(pages)).file;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Saved ${file.uri.pathSegments.last}')));
      await ref.read(pdfSharerProvider).send(file.path);
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not create the PDF. Try again.')));
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  void _start() {
    final state = ref.read(scanControllerProvider);
    final job = BatchOcrJob(
      engine: _engine,
      pages: [for (final id in widget.pageIds) ?state.pageById(id)],
      languageCode: widget.languageCode,
    );
    setState(() => _job = job);
    job.start();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.pageIds.length;
    final job = _job;
    // Pages are named by their place in the document, not in the selection.
    final order = [for (final p in ref.watch(scanControllerProvider).pages) p.id];
    int? numberOf(String id) {
      final i = order.indexOf(id);
      return i < 0 ? null : i + 1;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Recognize text')),
      body: FutureBuilder<OcrCapability>(
        future: _capability,
        builder: (context, snap) {
          final capability = snap.data;
          if (capability == null) return const Center(child: CircularProgressIndicator());
          if (job != null) {
            return ListenableBuilder(
              listenable: job,
              builder: (context, _) => _JobView(
                job: job,
                numberOf: numberOf,
                building: _building,
                onCreatePdf: () => _createPdf(job, numberOf),
              ),
            );
          }
          return _Intro(
            capability: capability,
            count: count,
            preparing: _preparing,
            onDownload: _download,
            onStart: _start,
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.capability,
    required this.count,
    required this.preparing,
    required this.onDownload,
    required this.onStart,
  });

  final OcrCapability capability;
  final int count;
  final bool preparing;
  final VoidCallback onDownload;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pages = '$count selected page${count == 1 ? '' : 's'}';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(pages, style: text.titleLarge),
        const SizedBox(height: 8),
        Text('Language: ${capability.language}', style: text.bodyLarge),
        const SizedBox(height: 4),
        Text('Text is read on this device, one page at a time. More pages take longer.', style: text.bodyMedium),
        const SizedBox(height: 24),
        switch (capability.readiness) {
          OcrReadiness.ready => FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: onStart,
            icon: const Icon(Icons.text_snippet_outlined),
            label: Text('Recognize text on $count page${count == 1 ? '' : 's'}'),
          ),
          OcrReadiness.needsDownload => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(capability.reason ?? 'Download ${capability.language} OCR to continue', style: text.bodyMedium),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: preparing ? null : onDownload,
                icon: preparing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined),
                label: Text('Download ${capability.language} OCR'),
              ),
            ],
          ),
          OcrReadiness.unavailable => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 12),
                  Expanded(child: Text(capability.reason ?? 'Text recognition is not available.')),
                ],
              ),
            ),
          ),
        },
      ],
    );
  }
}

class _JobView extends StatelessWidget {
  const _JobView({required this.job, required this.numberOf, required this.building, required this.onCreatePdf});

  final BatchOcrJob job;
  final int? Function(String pageId) numberOf;
  final bool building;
  final VoidCallback onCreatePdf;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final running = job.results.where((r) => r.status == OcrPageStatus.running).firstOrNull;
    final current = running == null ? null : numberOf(running.pageId) ?? job.currentNumber;
    final failed = job.withStatus(OcrPageStatus.failed).length + job.withStatus(OcrPageStatus.cancelled).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            job.running
                ? '${job.finished} of ${job.total} done${current == null ? '' : ', reading page $current'}'
                : 'Finished: ${job.withStatus(OcrPageStatus.done).length} with text, '
                      '${job.withStatus(OcrPageStatus.empty).length} without text, $failed not read',
            style: text.titleMedium,
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: job.total == 0 ? 1 : job.finished / job.total),
        const SizedBox(height: 16),
        if (job.running)
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: job.cancel,
            child: const Text('Cancel'),
          )
        else ...[
          if (job.withStatus(OcrPageStatus.done).isNotEmpty || job.withStatus(OcrPageStatus.empty).isNotEmpty) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: building ? null : onCreatePdf,
              icon: building
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Create text PDF'),
            ),
            const SizedBox(height: 8),
          ],
          if (failed > 0)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: job.retry,
              icon: const Icon(Icons.refresh),
              label: Text('Retry $failed page${failed == 1 ? '' : 's'}'),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
        const SizedBox(height: 16),
        for (final (i, r) in job.results.indexed) _ResultTile(number: numberOf(r.pageId) ?? i + 1, result: r),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.number, required this.result});

  final int number;
  final OcrPageResult result;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    final (icon, color, label) = switch (result.status) {
      OcrPageStatus.waiting => (Icons.schedule, colors.muted, 'Waiting'),
      OcrPageStatus.running => (Icons.hourglass_top, colors.accent, 'Reading'),
      OcrPageStatus.done => (Icons.check_circle_outline, colors.success, 'Text found'),
      OcrPageStatus.empty => (Icons.remove_circle_outline, colors.muted, 'No text found'),
      OcrPageStatus.failed => (Icons.error_outline, colors.danger, 'Failed'),
      OcrPageStatus.cancelled => (Icons.block, colors.muted, 'Cancelled'),
    };
    final preview = result.text?.trim().split('\n').first;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text('Page $number: $label'),
      subtitle: preview == null || preview.isEmpty ? null : Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
