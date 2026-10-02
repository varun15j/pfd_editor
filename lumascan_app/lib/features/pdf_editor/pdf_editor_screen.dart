import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/models.dart';
import '../../pdf_edit/annotations.dart';
import '../../pdf_edit/pdf_edit_controller.dart';
import 'annotation_layer.dart';
import 'organize_pages_screen.dart';
import 'save_pdf_sheet.dart';
import 'signature_pad_screen.dart';

/// Builds the image of one source page, sized by its parent.
typedef PageImageBuilder = Widget Function(EditorPage page, {bool thumbnail});

/// PDF editor: one page at a time with pinch zoom in View mode, pen,
/// highlighter, text, eraser and signature tools, page organizer and save.
class PdfEditorScreen extends ConsumerStatefulWidget {
  const PdfEditorScreen({super.key, required this.pageImage, this.onClosed});

  /// Editor for a document opened with pdfrx. The document is disposed when
  /// the screen closes.
  factory PdfEditorScreen.forDocument(PdfDocument document) => PdfEditorScreen(
    pageImage: (page, {thumbnail = false}) => PdfPageView(
      document: document,
      pageNumber: page.sourcePage,
      maximumDpi: thumbnail ? 72 : 300,
      decoration: const BoxDecoration(color: Colors.white),
    ),
    onClosed: document.dispose,
  );

  final PageImageBuilder pageImage;
  final VoidCallback? onClosed;

  @override
  ConsumerState<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends ConsumerState<PdfEditorScreen> {
  static const penColors = [Color(0xFF172D2A), Color(0xFF1E4FD8), Color(0xFFC62828), Color(0xFF086B61)];
  static const highlightColors = [Color(0xFFFFE53B), Color(0xFF7CF29C), Color(0xFFFF8AD8), Color(0xFF7CC8FF)];

  final _pageController = PageController();
  final _zoom = TransformationController();
  EditorTool _tool = EditorTool.view;
  Color _penColor = penColors.first;
  Color _highlightColor = highlightColors.first;
  int _index = 0;

  Color get _color => _tool == EditorTool.highlighter ? _highlightColor : _penColor;

  @override
  void dispose() {
    _pageController.dispose();
    _zoom.dispose();
    widget.onClosed?.call();
    super.dispose();
  }

  PdfEditController get _controller => ref.read(pdfEditControllerProvider.notifier);

  void _goTo(int index) {
    final count = ref.read(pdfEditControllerProvider).pages.length;
    final target = index.clamp(0, count - 1);
    _zoom.value = Matrix4.identity();
    setState(() => _index = target);
    if (_pageController.hasClients) _pageController.jumpToPage(target);
  }

  AnnotationCallbacks _callbacks(EditorPage page) => AnnotationCallbacks(
    newId: _controller.newId,
    onAdd: (a) => _controller.addAnnotation(page.id, a),
    onReplace: (a) => _controller.replaceAnnotation(page.id, a),
    onRemove: (id) => _controller.removeAnnotation(page.id, id),
    onPlaceText: (at) => _addText(page, at),
    onEditText: (a) => _editText(page, a),
    onItemMenu: (a) => _itemMenu(page, a),
  );

  Future<void> _addText(EditorPage page, NormPoint at) async {
    final text = await _askText(context, title: 'Add text');
    if (text == null || text.trim().isEmpty) return;
    _controller.addAnnotation(
      page.id,
      TextAnnotation(id: _controller.newId(), origin: at, text: text, color: _penColor.toARGB32()),
    );
  }

  Future<void> _editText(EditorPage page, TextAnnotation a) async {
    final text = await _askText(context, title: 'Edit text', initial: a.text, canDelete: true);
    if (text == null) return;
    if (text.trim().isEmpty) {
      _controller.removeAnnotation(page.id, a.id);
    } else if (text != a.text) {
      _controller.replaceAnnotation(page.id, a.copyWith(text: text));
    }
  }

  Future<void> _itemMenu(EditorPage page, Annotation a) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (a is TextAnnotation)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit text'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: const Text('Larger'),
              onTap: () => Navigator.pop(context, 'larger'),
            ),
            ListTile(
              leading: const Icon(Icons.zoom_out),
              title: const Text('Smaller'),
              onTap: () => Navigator.pop(context, 'smaller'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch ((action, a)) {
      case ('edit', TextAnnotation t):
        await _editText(page, t);
      case ('delete', _):
        _controller.removeAnnotation(page.id, a.id);
      case ('larger' || 'smaller', TextAnnotation t):
        final f = action == 'larger' ? 1.2 : 1 / 1.2;
        _controller.replaceAnnotation(page.id, t.copyWith(fontSize: (t.fontSize * f).clamp(0.01, 0.2)));
      case ('larger' || 'smaller', SignatureAnnotation s):
        final f = action == 'larger' ? 1.2 : 1 / 1.2;
        _controller.replaceAnnotation(page.id, s.copyWith(width: (s.width * f).clamp(0.08, 1.0)));
      default:
        break;
    }
  }

  Future<void> _addSignature(EditorPage page) async {
    final strokes = await SignaturePadScreen.show(context);
    if (strokes == null || !mounted) return;
    final signature = SignatureAnnotation.fromPadStrokes(
      id: _controller.newId(),
      strokes: strokes,
      color: 0xFF14213D,
      pageAspect: page.aspect,
    );
    if (signature == null) return;
    _controller.addAnnotation(page.id, signature);
    setState(() => _tool = EditorTool.select);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Drag the signature into place. Tap it to resize or delete.')));
  }

  Future<void> _organize() async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => OrganizePagesScreen(thumbnail: (page) => widget.pageImage(page, thumbnail: true)),
      ),
    );
    if (!mounted) return;
    _goTo(index ?? _index);
  }

  Future<bool> _confirmLeave() async {
    if (!ref.read(pdfEditControllerProvider).dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard your changes?'),
        content: const Text('Your marks and page changes have not been saved to a new PDF.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfEditControllerProvider);
    final pages = state.pages;
    if (pages.isEmpty) return const Scaffold(body: SizedBox.shrink());
    final index = _index.clamp(0, pages.length - 1);
    final page = pages[index];

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          _controller.close();
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.sourceName, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: state.canUndo ? _controller.undo : null,
            ),
            IconButton(tooltip: 'Organize pages', icon: const Icon(Icons.view_agenda_outlined), onPressed: _organize),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: FilledButton(onPressed: () => showSavePdfSheet(context), child: const Text('Save')),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                // Pages change with the arrows below so swipes never fight
                // with drawing or zooming.
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pages.length,
                itemBuilder: (context, i) => _PageCanvas(
                  key: ValueKey(pages[i].id),
                  page: pages[i],
                  image: widget.pageImage(pages[i]),
                  tool: _tool,
                  color: _color,
                  zoom: _zoom,
                  callbacks: _callbacks(pages[i]),
                ),
              ),
            ),
            _PageNavigator(
              index: index,
              count: pages.length,
              onPrevious: index > 0 ? () => _goTo(index - 1) : null,
              onNext: index < pages.length - 1 ? () => _goTo(index + 1) : null,
            ),
            _Toolbar(
              tool: _tool,
              onTool: (t) => setState(() => _tool = t),
              onSignature: () => _addSignature(page),
              colors: _tool == EditorTool.highlighter
                  ? highlightColors
                  : (_tool == EditorTool.pen || _tool == EditorTool.text)
                  ? penColors
                  : const [],
              color: _color,
              onColor: (c) => setState(() {
                if (_tool == EditorTool.highlighter) {
                  _highlightColor = c;
                } else {
                  _penColor = c;
                }
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// One page with its annotation overlay. In View mode the page can be
/// pinch-zoomed and panned. Other tools keep the zoom but drop the zoom
/// gestures entirely, so a finger draws or drags marks instead of moving
/// the page.
class _PageCanvas extends StatefulWidget {
  const _PageCanvas({
    super.key,
    required this.page,
    required this.image,
    required this.tool,
    required this.color,
    required this.zoom,
    required this.callbacks,
  });

  final EditorPage page;
  final Widget image;
  final EditorTool tool;
  final Color color;
  final TransformationController zoom;
  final AnnotationCallbacks callbacks;

  @override
  State<_PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends State<_PageCanvas> {
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
                AnnotationLayer(page: widget.page, tool: widget.tool, color: widget.color, callbacks: widget.callbacks),
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

class _PageNavigator extends StatelessWidget {
  const _PageNavigator({required this.index, required this.count, this.onPrevious, this.onNext});

  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(tooltip: 'Previous page', icon: const Icon(Icons.chevron_left), onPressed: onPrevious),
        Text('Page ${index + 1} of $count'),
        IconButton(tooltip: 'Next page', icon: const Icon(Icons.chevron_right), onPressed: onNext),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tool,
    required this.onTool,
    required this.onSignature,
    required this.colors,
    required this.color,
    required this.onColor,
  });

  final EditorTool tool;
  final ValueChanged<EditorTool> onTool;
  final VoidCallback onSignature;
  final List<Color> colors;
  final Color color;
  final ValueChanged<Color> onColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (colors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final c in colors)
                        Semantics(
                          button: true,
                          selected: c == color,
                          label: 'Colour',
                          child: InkResponse(
                            onTap: () => onColor(c),
                            radius: 22,
                            child: Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: c == color ? scheme.primary : scheme.outlineVariant,
                                  width: c == color ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              // Every tool stays visible, even on narrow phones.
              Row(
                children: [
                  for (final t in EditorTool.values)
                    Expanded(
                      child: _ToolButton(icon: t.icon, label: t.label, selected: t == tool, onTap: () => onTool(t)),
                    ),
                  Expanded(
                    child: _ToolButton(icon: Icons.draw_outlined, label: 'Sign', selected: false, onTap: onSignature),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.selected, required this.onTap});

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
          constraints: const BoxConstraints(minHeight: 52),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, style: Theme.of(context).textTheme.labelSmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for annotation text. Returns null when cancelled and an empty
/// string when the user chose Delete.
Future<String?> _askText(BuildContext context, {required String title, String initial = '', bool canDelete = false}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, canDelete: canDelete),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.canDelete});

  final String title;
  final String initial;
  final bool canDelete;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Type here'),
      ),
      actions: [
        if (widget.canDelete) TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Done')),
      ],
    );
  }
}
