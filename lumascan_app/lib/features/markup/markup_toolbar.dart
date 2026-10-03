import 'package:flutter/material.dart';

import '../pdf_editor/annotation_layer.dart';
import 'markup_style.dart';

/// The toolbar under a page being marked up: one colour and thickness picker
/// for the pen, highlighter and text tools, and a scrollable row of tools
/// that keeps the selected one in view. Used by the PDF editor and by the
/// scan markup screen.
class MarkupToolbar extends StatefulWidget {
  const MarkupToolbar({
    super.key,
    required this.tools,
    required this.tool,
    required this.onTool,
    required this.style,
    required this.onStyle,
    this.onSignature,
  });

  final List<EditorTool> tools;
  final EditorTool tool;
  final ValueChanged<EditorTool> onTool;
  final MarkupStyle style;
  final ValueChanged<MarkupStyle> onStyle;

  /// Adds a Sign button after the tools when set.
  final VoidCallback? onSignature;

  @override
  State<MarkupToolbar> createState() => _MarkupToolbarState();
}

class _MarkupToolbarState extends State<MarkupToolbar> {
  final _keys = <EditorTool, GlobalKey>{};

  bool get _showsStyle =>
      widget.tool == EditorTool.pen || widget.tool == EditorTool.highlighter || widget.tool == EditorTool.text;

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(MarkupToolbar old) {
    super.didUpdateWidget(old);
    if (old.tool != widget.tool) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _keys[widget.tool]?.currentContext;
      if (context == null || !context.mounted) return;
      Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = widget.style;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showsStyle)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          for (final c in MarkupStyle.palette)
                            Semantics(
                              button: true,
                              selected: c == style.color,
                              label: 'Colour',
                              child: InkResponse(
                                onTap: () => widget.onStyle(style.copyWith(color: c)),
                                radius: 22,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: c == style.color ? scheme.primary : scheme.outlineVariant,
                                      width: c == style.color ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          for (final s in MarkupSize.values)
                            ChoiceChip(
                              label: Text(s.label),
                              selected: s == style.size,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => widget.onStyle(style.copyWith(size: s)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final t in widget.tools)
                          _ToolButton(
                            key: _keys.putIfAbsent(t, GlobalKey.new),
                            icon: t.icon,
                            label: t.label,
                            selected: t == widget.tool,
                            onTap: () => widget.onTool(t),
                          ),
                        if (widget.onSignature != null)
                          _ToolButton(
                            icon: Icons.draw_outlined,
                            label: 'Sign',
                            selected: false,
                            onTap: widget.onSignature!,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52, minWidth: 68),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
