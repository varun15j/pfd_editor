import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'image_profiler.dart';
import 'profile_sample.dart';

/// Debug builds only: everything the image-loading profiler has saved,
/// averaged per kind of work and per screen, with the time of each step.
class ProfilingReportScreen extends ConsumerStatefulWidget {
  const ProfilingReportScreen({super.key});

  @override
  ConsumerState<ProfilingReportScreen> createState() => _ProfilingReportScreenState();
}

class _ProfilingReportScreenState extends ConsumerState<ProfilingReportScreen> {
  late Future<(List<ProfileSummaryRow>, List<ProfileSample>)> _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final store = ref.read(imageProfilerProvider).store;
    _data = Future.wait([store.summary(), store.recent(limit: 40)])
        .then((r) => (r[0] as List<ProfileSummaryRow>, r[1] as List<ProfileSample>));
  }

  @override
  Widget build(BuildContext context) {
    final profiler = ref.watch(imageProfilerProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image loading profile'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: () => setState(_load)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear profiling data',
            onPressed: () async {
              await profiler.clear();
              if (mounted) setState(_load);
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not read the profile: ${snap.error}'));
          final data = snap.data;
          if (data == null) return const Center(child: CircularProgressIndicator());
          final (rows, recent) = data;
          if (rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nothing measured yet. Swipe in from the left edge, turn on "Profile image loading", '
                'then open, edit and filter some pages.',
              ),
            );
          }
          final total = rows.fold(0, (n, r) => n + r.count);
          final photos = rows.where((r) => r.kind == ProfileKind.workingCopy).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('$total measurements', style: text.titleMedium),
              if (photos != null)
                Text(
                  'Photos: ${photos.count} decoded, ${photos.avgSourceMb.toStringAsFixed(2)} MB on average, '
                  '${formatProfileMs(photos.avgMs)} each to make the working copies.',
                ),
              const SizedBox(height: 16),
              for (final kind in ProfileKind.values) ...[
                if (rows.any((r) => r.kind == kind)) ...[
                  Text(kind.label, style: text.titleMedium),
                  const SizedBox(height: 4),
                  for (final row in rows.where((r) => r.kind == kind)) _SummaryCard(row),
                  const SizedBox(height: 12),
                ],
              ],
              Text('Latest', style: text.titleMedium),
              for (final s in recent)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text([s.kind.label, ?s.screen, ?s.origin?.label].join(' · ')),
                  subtitle: Text(
                    '${s.width}×${s.height}'
                    '${s.sourceBytes > 0 ? ' from ${s.sourceMb.toStringAsFixed(2)} MB' : ''}'
                    '${s.filter != null ? ' · ${s.filter}' : ''}',
                  ),
                  trailing: Text(
                    formatProfileMs(s.totalMs),
                    style: const TextStyle(color: Color(0xFFD50000), fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.row);

  final ProfileSummaryRow row;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stages = [
      for (final s in profileStages)
        if (row.avgStageMs[s] case final ms? when ms > 0) '$s ${formatProfileMs(ms)}',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(row.screen ?? 'All screens', style: text.titleSmall)),
                Text(
                  'avg ${formatProfileMs(row.avgMs)}',
                  style: const TextStyle(color: Color(0xFFD50000), fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Text(
              '${row.count} times · fastest ${formatProfileMs(row.minMs)} · slowest ${formatProfileMs(row.maxMs)}'
              '${row.avgWaitMs > 0.5 ? ' · waited ${formatProfileMs(row.avgWaitMs)} for a free slot' : ''}',
              style: text.bodySmall,
            ),
            if (row.avgSourceMb > 0)
              Text('Source ${row.avgSourceMb.toStringAsFixed(2)} MB on average', style: text.bodySmall),
            if (stages.isNotEmpty) Text('Steps: ${stages.join(' · ')}', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
