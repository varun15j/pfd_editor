import 'package:flutter/material.dart';

import '../../ui/compact_action_button.dart';
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
      widget.tool == EditorTool.pen ||
      widget.tool == EditorTool.highlighter ||
      widget.tool == EditorTool.text;

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
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
      );
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
                          for (var i = 0; i < MarkupStyle.palette.length; i++)
                            _Swatch(
                              color: MarkupStyle.palette[i],
                              name: MarkupStyle.paletteNames[i],
                              selected: MarkupStyle.palette[i] == style.color,
                              onTap: () => widget.onStyle(
                                style.copyWith(color: MarkupStyle.palette[i]),
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
                              onSelected: (_) =>
                                  widget.onStyle(style.copyWith(size: s)),
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
                          CompactActionButton(
                            key: _keys.putIfAbsent(t, GlobalKey.new),
                            icon: t.icon,
                            label: t.label,
                            selected: t == widget.tool,
                            minWidth: 60,
                            onPressed: () => widget.onTool(t),
                          ),
                        if (widget.onSignature != null)
                          CompactActionButton(
                            icon: Icons.draw_outlined,
                            label: 'Sign',
                            selected: false,
                            minWidth: 60,
                            onPressed: widget.onSignature!,
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

/// One colour in the picker. The circle is small, the tap area is not.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name ink',
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
