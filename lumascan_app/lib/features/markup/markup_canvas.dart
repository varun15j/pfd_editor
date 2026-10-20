import 'package:flutter/material.dart';

import '../../pdf_edit/annotations.dart';
import '../pdf_editor/annotation_layer.dart';
import 'markup_style.dart';

/// One page with its annotation overlay. In View mode the page can be
/// pinch-zoomed and panned. Other tools keep the zoom but drop the zoom
/// gestures entirely, so a finger draws or drags marks instead of moving
/// the page.
class MarkupCanvas extends StatefulWidget {
  const MarkupCanvas({
    super.key,
    required this.page,
    required this.image,
    required this.tool,
    required this.style,
    required this.zoom,
    required this.callbacks,
  });

  final EditorPage page;
  final Widget image;
  final EditorTool tool;
  final MarkupStyle style;
  final TransformationController zoom;
  final AnnotationCallbacks callbacks;

  @override
  State<MarkupCanvas> createState() => _MarkupCanvasState();
}

class _MarkupCanvasState extends State<MarkupCanvas> {
  // Keeps the rendered page and overlay alive when switching between the
  // zoomable and the fixed wrapper.
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final content = Center(
      key: _contentKey,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AspectRatio(
          aspectRatio: widget.page.aspect,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.image,
                AnnotationLayer(page: widget.page, tool: widget.tool, style: widget.style, callbacks: widget.callbacks),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.tool == EditorTool.view) {
      return InteractiveViewer(transformationController: widget.zoom, minScale: 1, maxScale: 5, child: content);
    }
    return ClipRect(
      child: Transform(transform: widget.zoom.value, child: content),
    );
  }
}
