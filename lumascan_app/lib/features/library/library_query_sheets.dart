import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/library.dart';
import '../../domain/library_query.dart';
import 'library_controller.dart';
import 'library_query_controller.dart';

Future<void> showSortSheet(BuildContext context) =>
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => const SortSheet());

Future<void> showFilterSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const FilterSheet(),
);

/// Sort choices; the active one has a filled radio and a check, and is
/// announced as selected.
class SortSheet extends ConsumerWidget {
  const SortSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(libraryQueryProvider.select((q) => q.sort));
    final c = LumaColors.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: RadioGroup<LibrarySort>(
          groupValue: current,
          onChanged: (s) {
            if (s != null) ref.read(libraryQueryProvider.notifier).sortBy(s);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                child: Semantics(header: true, child: Text('Sort by', style: Theme.of(context).textTheme.titleLarge)),
              ),
              for (final s in LibrarySort.values)
                RadioListTile<LibrarySort>(
                  value: s,
                  title: Text(s.label),
                  secondary: s == current ? Icon(Icons.check, color: c.accent) : null,
                ),
              const SizedBox(height: Space.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// Type and date filters. Changes apply on "Show results"; a custom range
/// with From after To is rejected inline.
class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key});

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late final LibraryQuery _start = ref.read(libraryQueryProvider);
  late Set<ScanType> _types = {..._start.types};
  late DateFilter _date = _start.date;
  late DateTime? _from = _start.from;
  late DateTime? _to = _start.to;
  late Set<String> _tags = {..._start.tags};

  String? get _rangeError => _date == DateFilter.custom ? LibraryQuery.rangeError(_from, _to) : null;

  Future<void> _pick({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: from ? 'From' : 'To',
    );
    if (picked != null) setState(() => from ? _from = picked : _to = picked);
  }

  void _apply() {
    ref.read(libraryQueryProvider.notifier).filter(types: _types, date: _date, from: _from, to: _to, tags: _tags);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = _rangeError;
    final allTags = ref.watch(libraryProvider).value?.allTags ?? const <String>[];
    String day(DateTime? d) => d == null ? 'Pick a date' : MaterialLocalizations.of(context).formatMediumDate(d);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Filter', style: text.titleLarge)),
            const SizedBox(height: Space.lg),
            Text('Type', style: text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final t in ScanType.values)
                  FilterChip(
                    label: Text(t.label),
                    selected: _types.contains(t),
                    onSelected: (on) => setState(() => _types = on ? {..._types, t} : ({..._types}..remove(t))),
                  ),
              ],
            ),
            if (allTags.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('Tags', style: text.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final t in allTags)
                    FilterChip(
                      label: Text(t),
                      selected: _tags.contains(t.toLowerCase()),
                      onSelected: (on) => setState(
                        () => _tags = on ? {..._tags, t.toLowerCase()} : ({..._tags}..remove(t.toLowerCase())),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.xl),
            Text('Date changed', style: text.titleSmall),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final d in DateFilter.values)
                  ChoiceChip(label: Text(d.label), selected: _date == d, onSelected: (_) => setState(() => _date = d)),
              ],
            ),
            if (_date == DateFilter.custom) ...[
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(from: true),
                      child: Text('From: ${day(_from)}', textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pick(from: false),
                      child: Text('To: ${day(_to)}', textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: Space.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(error, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            ],
            const SizedBox(height: Space.xl),
            FilledButton(onPressed: error == null ? _apply : null, child: const Text('Show results')),
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => setState(() {
                _types = {};
                _tags = {};
                _date = DateFilter.any;
                _from = null;
                _to = null;
              }),
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}
