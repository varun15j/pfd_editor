import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../imaging/render_service.dart';
import '../crop/crop_screen.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';

/// Enhance screen (S04): document filters, rotation, before/after and
/// apply-to-all. Edits are kept local until Save.
class FilterScreen extends ConsumerStatefulWidget {
  const FilterScreen({super.key, required this.pageId});

  final String pageId;

  @override
  ConsumerState<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends ConsumerState<FilterScreen> {
  EditRecipe? _draft;
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(scanControllerProvider.select((s) => s.pageById(widget.pageId)));
    if (page == null) return const Scaffold(body: SizedBox.shrink());
    // Pick up crop changes made on the crop screen while keeping local edits.
    final draft = (_draft ?? page.recipe).copyWith(crop: page.recipe.crop);
    final shown = _showOriginal ? draft.copyWith(filter: DocumentFilter.original) : draft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhance'),
        actions: [
          IconButton(
            tooltip: 'Crop',
            icon: const Icon(Icons.crop),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id)),
            ),
          ),
          IconButton(
            tooltip: 'Rotate left',
            icon: const Icon(Icons.rotate_left),
            onPressed: () => setState(() => _draft = draft.copyWith(quarterTurns: draft.quarterTurns + 3)),
          ),
          IconButton(
            tooltip: 'Rotate right',
            icon: const Icon(Icons.rotate_right),
            onPressed: () => setState(() => _draft = draft.copyWith(quarterTurns: draft.quarterTurns + 1)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              // Press and hold to compare with the unfiltered page.
              onLongPressStart: (_) => setState(() => _showOriginal = true),
              onLongPressEnd: (_) => setState(() => _showOriginal = false),
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: LumaColors.of(context).surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(16),
                child: PageImage(page: page, recipe: shown, maxDimension: RenderService.previewSize),
              ),
            ),
          ),
          Text(
            _showOriginal ? 'Showing original' : 'Hold the page to compare with the original',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SizedBox(
            height: 128,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final f in DocumentFilter.values)
                  _FilterChoice(
                    page: page,
                    recipe: draft.copyWith(filter: f),
                    selected: draft.filter == f,
                    onTap: () => setState(() => _draft = draft.copyWith(filter: f)),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () {
                    final controller = ref.read(scanControllerProvider.notifier);
                    controller.updateRecipe(page.id, draft);
                    controller.applyFilterToAll(draft.filter);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${draft.filter.label} applied to all pages')),
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply to all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (draft != page.recipe) {
                      ref.read(scanControllerProvider.notifier).updateRecipe(page.id, draft);
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({required this.page, required this.recipe, required this.selected, required this.onTap});

  final ScanPage page;
  final EditRecipe recipe;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final teal = Theme.of(context).colorScheme.primary;
    return Semantics(
      selected: selected,
      button: true,
      label: '${recipe.filter.label} filter',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              Container(
                height: 78,
                width: 70,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: selected ? LumaColors.of(context).accentSoft : LumaColors.of(context).surfaceRaised,
                  border: Border.all(color: selected ? teal : Colors.transparent, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: PageImage(page: page, recipe: recipe, maxDimension: 240),
              ),
              const SizedBox(height: 6),
              Text(
                recipe.filter.label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? teal : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
