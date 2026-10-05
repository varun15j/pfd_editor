import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../imaging/render_service.dart';
import '../../ui/undo_toast.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';

/// Enhance Selected Pages (BE-04): one look (filter, brightness, contrast)
/// for every selected page. The preview shows one selected page at a time.
/// Only the enhancement is copied; each page keeps its own crop, rotation,
/// marks and original image.
class BatchEnhanceScreen extends ConsumerStatefulWidget {
  const BatchEnhanceScreen({super.key, required this.pageIds});

  /// The selected pages, in document order.
  final List<String> pageIds;

  @override
  ConsumerState<BatchEnhanceScreen> createState() => _BatchEnhanceScreenState();
}

class _BatchEnhanceScreenState extends ConsumerState<BatchEnhanceScreen> {
  int _active = 0;
  EditRecipe? _look;
  bool _showOriginal = false;

  static const _plain = EditRecipe();

  void _apply(EditRecipe look) {
    final controller = ref.read(scanControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    controller.applyEnhancementToPages(widget.pageIds.toSet(), look);
    final count = widget.pageIds.length;
    showUndoToast(messenger, message: 'Enhanced $count page${count == 1 ? '' : 's'}', onUndo: controller.undo);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final pages = [for (final id in widget.pageIds) ?state.pageById(id)];
    if (pages.isEmpty) return const Scaffold(body: SizedBox.shrink());
    final active = pages[_active.clamp(0, pages.length - 1)];
    final look =
        _look ??
        _plain.copyWith(
          filter: active.recipe.filter,
          brightness: active.recipe.brightness,
          contrast: active.recipe.contrast,
        );
    EditRecipe onPage(ScanPage page, EditRecipe look) =>
        page.recipe.copyWith(filter: look.filter, brightness: look.brightness, contrast: look.contrast);
    final shown = _showOriginal ? onPage(active, _plain) : onPage(active, look);
    final count = pages.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Enhance $count page${count == 1 ? '' : 's'}'),
        actions: [TextButton(onPressed: () => setState(() => _look = _plain), child: const Text('Reset'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: Semantics(
              image: true,
              label: 'Page ${_active + 1} of $count selected${_showOriginal ? ', original' : ''}',
              excludeSemantics: true,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LumaColors.of(context).surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PageImage(
                  page: active,
                  recipe: shown,
                  maxDimension: RenderService.previewSize,
                  showMarks: false,
                ),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous selected page',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _active > 0 ? () => setState(() => _active--) : null,
                      ),
                      Expanded(
                        child: Text(
                          'Page ${_active + 1} of $count',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next selected page',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _active < count - 1 ? () => setState(() => _active++) : null,
                      ),
                    ],
                  ),
                  SwitchListTile(
                    title: const Text('Compare with original'),
                    value: _showOriginal,
                    onChanged: (v) => setState(() => _showOriginal = v),
                  ),
                  SizedBox(
                    height: 108 + MediaQuery.textScalerOf(context).scale(11) * 1.5,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        for (final f in DocumentFilter.values)
                          _FilterThumb(
                            page: active,
                            recipe: onPage(active, look.copyWith(filter: f)),
                            label: f.label,
                            selected: look.filter == f,
                            onTap: () => setState(() => _look = look.copyWith(filter: f)),
                          ),
                      ],
                    ),
                  ),
                  _Adjust(
                    label: 'Brightness',
                    value: look.brightness,
                    onChanged: (v) => setState(() => _look = look.copyWith(brightness: v)),
                  ),
                  _Adjust(
                    label: 'Contrast',
                    value: look.contrast,
                    onChanged: (v) => setState(() => _look = look.copyWith(contrast: v)),
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
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => _apply(look),
                  child: Text('Apply to $count page${count == 1 ? '' : 's'}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterThumb extends StatelessWidget {
  const _FilterThumb({
    required this.page,
    required this.recipe,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ScanPage page;
  final EditRecipe recipe;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = LumaColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 64,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? colors.accent : colors.line, width: selected ? 2.5 : 1),
                ),
                padding: const EdgeInsets.all(3),
                child: PageImage(page: page, recipe: recipe, showMarks: false),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A -100% to +100% slider.
class _Adjust extends StatelessWidget {
  const _Adjust({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = '${value >= 0 ? '+' : ''}${(value * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: -1,
              max: 1,
              divisions: 40,
              label: percent,
              semanticFormatterCallback: (_) => percent,
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 48, child: Text(percent, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
