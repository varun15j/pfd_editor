import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../imaging/render_service.dart';
import '../../ui/undo_toast.dart';
import '../crop/crop_screen.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';

/// Enhance screen (S04): filter presets, brightness and contrast, rotation and
/// before/after. Edits are kept local until Apply, which asks which pages they
/// are for.
class FilterScreen extends ConsumerStatefulWidget {
  const FilterScreen({super.key, required this.pageId});

  final String pageId;

  @override
  ConsumerState<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends ConsumerState<FilterScreen> {
  EditRecipe? _draft;
  bool _showOriginal = false;

  // Slider values while a thumb is being dragged. The page is only re-rendered
  // when the drag ends, so dragging stays smooth.
  double? _liveBrightness;
  double? _liveContrast;

  Future<void> _apply(ScanPage page, EditRecipe draft) async {
    final controller = ref.read(scanControllerProvider.notifier);
    final pages = ref.read(scanControllerProvider).pages;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    var targets = <String>{page.id};
    if (pages.length > 1) {
      final picked = await showEnhanceScopeSheet(context, pages: pages, currentId: page.id, draft: draft);
      if (picked == null || !mounted) return;
      targets = picked;
    }
    final others = targets.difference({page.id});
    if (draft == page.recipe && others.isEmpty) {
      navigator.pop();
      return;
    }
    final dropsMarks = controller.dropsMarks(page.id, draft);
    controller.applyEnhancement(page.id, draft, alsoPageIds: others);
    final count = targets.length;
    showUndoToast(
      messenger,
      message:
          '${count == 1 ? 'Changes applied to this page' : 'Changes applied to $count pages'}'
          '${dropsMarks ? '. Markup removed from this page because it was rotated' : ''}',
      onUndo: controller.undo,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(scanControllerProvider.select((s) => s.pageById(widget.pageId)));
    if (page == null) return const Scaffold(body: SizedBox.shrink());
    // Pick up crop changes made on the crop screen while keeping local edits.
    final draft = (_draft ?? page.recipe).copyWith(crop: page.recipe.crop);
    final shown = _showOriginal ? draft.copyWith(filter: DocumentFilter.original, brightness: 0, contrast: 0) : draft;
    final brightness = _liveBrightness ?? draft.brightness;
    final contrast = _liveContrast ?? draft.contrast;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhance'),
        actions: [
          IconButton(
            tooltip: 'Crop',
            icon: const Icon(Icons.crop),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id))),
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
                child: PageImage(page: page, recipe: shown, maxDimension: RenderService.previewSize, showMarks: false),
              ),
            ),
          ),
          // The controls scroll when they do not fit (small screens, large
          // text), so the page above always keeps room.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Text(
                    _showOriginal ? 'Showing original' : 'Press and hold the page to see the original',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  SizedBox(
                    // Thumbnail, gaps and one line of label, which grows with the text size.
                    height: 108 + MediaQuery.textScalerOf(context).scale(11) * 1.5,
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
                  _AdjustSlider(
                    label: 'Brightness',
                    value: brightness,
                    onChanged: (v) => setState(() => _liveBrightness = v),
                    onChangeEnd: (v) => setState(() {
                      _draft = draft.copyWith(brightness: v);
                      _liveBrightness = null;
                    }),
                  ),
                  _AdjustSlider(
                    label: 'Contrast',
                    value: contrast,
                    onChanged: (v) => setState(() => _liveContrast = v),
                    onChangeEnd: (v) => setState(() {
                      _draft = draft.copyWith(contrast: v);
                      _liveContrast = null;
                    }),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextButton(
                        onPressed: draft.hasAdjustments
                            ? () => setState(() => _draft = draft.copyWith(brightness: 0, contrast: 0))
                            : null,
                        child: const Text('Reset adjustments'),
                      ),
                    ),
                  ),
                ],
              ),
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(onPressed: () => _apply(page, draft), child: const Text('Apply')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A -100% to +100% slider that reads out its value.
class _AdjustSlider extends StatelessWidget {
  const _AdjustSlider({required this.label, required this.value, required this.onChanged, required this.onChangeEnd});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round();
    final text = percent > 0 ? '+$percent%' : '$percent%';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(
            child: Slider(
              value: value,
              min: -1,
              max: 1,
              divisions: 40,
              label: text,
              semanticFormatterCallback: (_) => '$label $text',
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(text, textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
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
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 76,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              // The selected preset has both a border and a check, so it never
              // relies on colour alone.
              Stack(
                clipBehavior: Clip.none,
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
                    child: PageImage(page: page, recipe: recipe, maxDimension: 240, showMarks: false),
                  ),
                  if (selected)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        decoration: BoxDecoration(color: teal, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                recipe.filter.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

enum _Scope { thisPage, selected, all }

/// Asks which pages the enhancement is for. Returns their ids (always including
/// [currentId] for "this page"), or null when the user cancels.
Future<Set<String>?> showEnhanceScopeSheet(
  BuildContext context, {
  required List<ScanPage> pages,
  required String currentId,
  required EditRecipe draft,
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ScopeSheet(pages: pages, currentId: currentId, draft: draft),
);

class _ScopeSheet extends StatefulWidget {
  const _ScopeSheet({required this.pages, required this.currentId, required this.draft});

  final List<ScanPage> pages;
  final String currentId;
  final EditRecipe draft;

  @override
  State<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<_ScopeSheet> {
  _Scope _scope = _Scope.thisPage;
  late final Set<String> _selected = {widget.currentId};

  Set<String> get _result => switch (_scope) {
    _Scope.thisPage => {widget.currentId},
    _Scope.selected => _selected,
    _Scope.all => {for (final p in widget.pages) p.id},
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canApply = _result.isNotEmpty;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Apply to', style: textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${widget.draft.filter.label} filter, brightness and contrast are copied. '
              'Crop and rotation stay as they are on each page.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _ScopeOption(
              label: 'This page',
              selected: _scope == _Scope.thisPage,
              onTap: () => setState(() => _scope = _Scope.thisPage),
            ),
            _ScopeOption(
              label: 'Selected pages',
              selected: _scope == _Scope.selected,
              onTap: () => setState(() => _scope = _Scope.selected),
            ),
            if (_scope == _Scope.selected)
              for (var i = 0; i < widget.pages.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 32),
                  title: Text('Page ${i + 1}'),
                  value: _selected.contains(widget.pages[i].id),
                  onChanged: (on) => setState(() {
                    if (on ?? false) {
                      _selected.add(widget.pages[i].id);
                    } else {
                      _selected.remove(widget.pages[i].id);
                    }
                  }),
                ),
            _ScopeOption(
              label: 'All ${widget.pages.length} pages',
              selected: _scope == _Scope.all,
              onTap: () => setState(() => _scope = _Scope.all),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canApply ? () => Navigator.pop(context, _result) : null,
              child: Text(switch (_scope) {
                _Scope.thisPage => 'Apply to this page',
                _Scope.selected => 'Apply to ${_selected.length} page${_selected.length == 1 ? '' : 's'}',
                _Scope.all => 'Apply to all pages',
              }),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
        title: Text(label),
      ),
    );
  }
}
