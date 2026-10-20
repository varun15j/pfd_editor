import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/models.dart';
import '../../pdf_edit/annotations.dart';
import '../../pdf_edit/pdf_edit_controller.dart';
import '../markup/markup_actions.dart';
import '../markup/markup_canvas.dart';
import '../markup/markup_style.dart';
import '../markup/markup_toolbar.dart';
import 'annotation_layer.dart';
import 'organize_pages_screen.dart';
import 'save_pdf_sheet.dart';
import 'signature_pad_screen.dart';

/// Builds the image of one source page, sized by its parent.
typedef PageImageBuilder = Widget Function(EditorPage page, {bool thumbnail});

/// What the editor does as soon as it opens, for the Tools shortcuts.
enum PdfEditorEntry {
  /// Just the editor, in View mode.
  edit,

  /// Opens the signature pad on the first page.
  sign,

  /// Opens the page organizer.
  organize,
}

/// PDF editor: one page at a time with pinch zoom in View mode, pen,
/// highlighter, text, eraser and signature tools, page organizer and save.
class PdfEditorScreen extends ConsumerStatefulWidget {
  const PdfEditorScreen({super.key, required this.pageImage, this.onClosed, this.entry = PdfEditorEntry.edit});

  /// Editor for a document opened with pdfrx. The document is disposed when
  /// the screen closes.
  factory PdfEditorScreen.forDocument(PdfDocument document, {PdfEditorEntry entry = PdfEditorEntry.edit}) =>
      PdfEditorScreen(
        entry: entry,
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
  final PdfEditorEntry entry;

  @override
  ConsumerState<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends ConsumerState<PdfEditorScreen> {
  final _pageController = PageController();
  final _zoom = TransformationController();
  EditorTool _tool = EditorTool.view;
  MarkupStyle _style = const MarkupStyle();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.entry == PdfEditorEntry.edit) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pages = ref.read(pdfEditControllerProvider).pages;
      if (pages.isEmpty) return;
      switch (widget.entry) {
        case PdfEditorEntry.sign:
          _addSignature(pages.first);
        case PdfEditorEntry.organize:
          _organize();
        case PdfEditorEntry.edit:
          break;
      }
    });
  }

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
    final text = await askAnnotationText(context, title: 'Add text');
    if (text == null || text.trim().isEmpty) return;
    _controller.addAnnotation(
      page.id,
      TextAnnotation(
        id: _controller.newId(),
        origin: at,
        text: text,
        color: _style.color.toARGB32(),
        fontSize: _style.fontSize,
      ),
    );
  }

  Future<void> _editText(EditorPage page, TextAnnotation a) async {
    final text = await askAnnotationText(context, title: 'Edit text', initial: a.text, canDelete: true);
    if (text == null) return;
    if (text.trim().isEmpty) {
      _controller.removeAnnotation(page.id, a.id);
    } else if (text != a.text) {
      _controller.replaceAnnotation(page.id, a.copyWith(text: text));
    }
  }

  Future<void> _itemMenu(EditorPage page, Annotation a) async {
    final action = await showAnnotationMenu(context, a);
    if (action == null) return;
    switch ((action, a)) {
      case (AnnotationMenuAction.edit, TextAnnotation t):
        await _editText(page, t);
      case (AnnotationMenuAction.delete, _):
        _controller.removeAnnotation(page.id, a.id);
      case (AnnotationMenuAction.larger || AnnotationMenuAction.smaller, _):
        _controller.replaceAnnotation(page.id, resizedAnnotation(a, larger: action == AnnotationMenuAction.larger));
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
                itemBuilder: (context, i) => MarkupCanvas(
                  key: ValueKey(pages[i].id),
                  page: pages[i],
                  image: widget.pageImage(pages[i]),
                  tool: _tool,
                  style: _style,
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
            MarkupToolbar(
              tools: EditorTool.values,
              tool: _tool,
              onTool: (t) => setState(() => _tool = t),
              style: _style,
              onStyle: (v) => setState(() => _style = v),
              onSignature: () => _addSignature(page),
            ),
          ],
        ),
      ),
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
