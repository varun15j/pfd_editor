import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/ocr.dart';
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
              builder: (context, _) => _JobView(job: job),
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
  const _JobView({required this.job});

  final BatchOcrJob job;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = job.currentNumber;
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
        for (final (i, r) in job.results.indexed) _ResultTile(number: i + 1, result: r),
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
