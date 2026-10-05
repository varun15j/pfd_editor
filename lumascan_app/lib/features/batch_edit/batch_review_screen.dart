import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../capture/add_pages_sheet.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';
import 'batch_selection.dart';

/// Batch Review (BE-02, US-03.5): every page of the draft in a two-column
/// grid. Tap pages to pick which ones the batch actions apply to. All pages
/// start selected, because opening this screen means editing the batch.
class BatchReviewScreen extends ConsumerStatefulWidget {
  const BatchReviewScreen({super.key});

  @override
  ConsumerState<BatchReviewScreen> createState() => _BatchReviewScreenState();
}

class _BatchReviewScreenState extends ConsumerState<BatchReviewScreen> {
  late BatchSelection _selection = BatchSelection.all(ref.read(scanControllerProvider).pages);

  void _select(BatchSelection selection) => setState(() => _selection = selection);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final pages = state.pages;
    // Deleted pages leave the selection; the rest stays as it was.
    _selection = _selection.retain(pages);

    return Scaffold(
      appBar: AppBar(title: const Text('Batch review')),
      body: Column(
        children: [
          _SelectionRow(
            selection: _selection,
            allSelected: _selection.coversAll(pages),
            busy: state.busy,
            onSelectAll: () => _select(BatchSelection.all(pages)),
            onClear: () => _select(const BatchSelection()),
            onAddPages: () => showAddPagesSheet(context, ref),
          ),
          Expanded(
            child: pages.isEmpty
                ? const Center(child: Text('No pages in this document'))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.68,
                    ),
                    itemCount: pages.length,
                    itemBuilder: (context, i) => BatchPageTile(
                      key: ValueKey(pages[i].id),
                      page: pages[i],
                      number: i + 1,
                      selected: _selection.contains(pages[i].id),
                      onTap: () => _select(_selection.toggle(pages[i].id)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Selected count, Select all or Clear, and Add pages.
class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.selection,
    required this.allSelected,
    required this.busy,
    required this.onSelectAll,
    required this.onClear,
    required this.onAddPages,
  });

  final BatchSelection selection;
  final bool allSelected;
  final bool busy;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onAddPages;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                '${selection.count} selected',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: allSelected ? onClear : onSelectAll,
            child: Text(allSelected ? 'Clear' : 'Select all'),
          ),
          IconButton(
            tooltip: 'Add pages',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: busy ? null : onAddPages,
          ),
        ],
      ),
    );
  }
}

/// One page in the Batch Review grid: thumbnail, page number and a check
/// that shows whether it is selected. The check is drawn with an icon as
/// well as colour, so selection never depends on colour alone.
class BatchPageTile extends StatelessWidget {
  const BatchPageTile({
    super.key,
    required this.page,
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final ScanPage page;
  final int number;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Page $number',
      hint: selected ? 'Selected. Tap to leave out' : 'Tap to select',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected ? colors.accentSoft : colors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? colors.accent : colors.line, width: selected ? 2.5 : 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PageImage(page: page),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? colors.accent : colors.surface,
                        border: Border.all(color: selected ? colors.accent : colors.muted, width: 2),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        selected ? Icons.check : Icons.circle_outlined,
                        size: 18,
                        color: selected ? colors.onAccent : Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Page $number',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
