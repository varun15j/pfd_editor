import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../domain/id_masking.dart';
import '../../domain/models.dart';
import '../../domain/ocr.dart';
import '../../domain/plan.dart';
import '../../imaging/page_renderer.dart';
import '../../imaging/render_service.dart';
import '../../pdf_edit/annotations.dart';
import '../../ui/upgrade_dialog.dart';
import '../pages/scan_controller.dart';
import '../pdf_editor/annotation_layer.dart';
import '../signatures/sign_sheet.dart';
import 'markup_actions.dart';
import 'markup_canvas.dart';
import 'markup_style.dart';
import 'markup_toolbar.dart';

/// Pen, highlighter, text, mask, eraser and signature on a scanned page. It uses the
/// same overlay and toolbar as the PDF editor. Marks are kept on the screen
/// until Done, so leaving with Back never changes the page, and Done is one
/// undo step in the draft.
class MarkupScreen extends ConsumerStatefulWidget {
  const MarkupScreen({super.key, required this.pageId, this.initialTool = EditorTool.pen});

  final String pageId;

  /// The tool selected when the screen opens: Mask from ID card mode.
  final EditorTool initialTool;

  @override
  ConsumerState<MarkupScreen> createState() => _MarkupScreenState();
}

class _MarkupScreenState extends ConsumerState<MarkupScreen> {
  final _zoom = TransformationController();
  Future<RenderedImage>? _image;
  List<Annotation>? _marks;
  final _undo = <List<Annotation>>[];
  late EditorTool _tool = widget.initialTool;
  MarkupStyle _style = const MarkupStyle();
  bool _autoMasking = false;

  /// True once something changed since the screen opened.
  bool get _dirty => _undo.isNotEmpty;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  String _newId() => ref.read(pageStoreProvider).newId();

  void _change(List<Annotation> next) {
    setState(() {
      _undo.add(_marks!);
      _marks = List.unmodifiable(next);
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() => _marks = _undo.removeLast());
  }

  AnnotationCallbacks _callbacks(EditorPage page) => AnnotationCallbacks(
    newId: _newId,
    onAdd: (a) => _change([..._marks!, a]),
    onReplace: (a) => _change([for (final x in _marks!) x.id == a.id ? a : x]),
    onRemove: (id) => _change([
      for (final x in _marks!)
        if (x.id != id) x,
    ]),
    onPlaceText: (at) => _addText(at),
    onEditText: _editText,
    onItemMenu: (a) => _itemMenu(page, a),
  );

  Future<void> _addText(NormPoint at) async {
    final text = await askAnnotationText(context, title: 'Add text');
    if (text == null || text.trim().isEmpty || !mounted) return;
    _change([
      ..._marks!,
      TextAnnotation(id: _newId(), origin: at, text: text, color: _style.color.toARGB32(), fontSize: _style.fontSize),
    ]);
  }

  Future<void> _editText(TextAnnotation a) async {
    final text = await askAnnotationText(context, title: 'Edit text', initial: a.text, canDelete: true);
    if (text == null || !mounted) return;
    if (text.trim().isEmpty) {
      _change([
        for (final x in _marks!)
          if (x.id != a.id) x,
      ]);
    } else if (text != a.text) {
      _change([for (final x in _marks!) x.id == a.id ? a.copyWith(text: text) : x]);
    }
  }

  Future<void> _itemMenu(EditorPage page, Annotation a) async {
    final action = await showAnnotationMenu(context, a);
    if (action == null || !mounted) return;
    switch ((action, a)) {
      case (AnnotationMenuAction.edit, TextAnnotation t):
        await _editText(t);
      case (AnnotationMenuAction.delete, _):
        _change([
          for (final x in _marks!)
            if (x.id != a.id) x,
        ]);
      case (AnnotationMenuAction.larger || AnnotationMenuAction.smaller, _):
        final resized = resizedAnnotation(a, larger: action == AnnotationMenuAction.larger);
        _change([for (final x in _marks!) x.id == a.id ? resized : x]);
      default:
        break;
    }
  }

  Future<void> _addSignature(EditorPage page) async {
    final mark = await chooseSignatureOrStamp(context, ref, newId: _newId, pageAspect: page.aspect);
    if (mark == null || !mounted) return;
    _change([..._marks!, mark]);
    setState(() => _tool = EditorTool.select);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Drag it into place. Tap it to resize or delete.')));
  }

  /// Reads the page on the device and masks every ID number found, leaving
  /// the last four characters. The masks are ordinary marks: they can be
  /// moved, resized or removed, and Undo takes them all back at once.
  Future<void> _autoMask(ScanPage page) async {
    if (!await ensurePlan(context, ref, PlanFeature.autoMask, what: 'Auto mask')) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final engine = ref.read(ocrEngineProvider);
    final capability = await engine.capability('en');
    if (engine is! OcrLayoutEngine || capability.readiness == OcrReadiness.unavailable) {
      say(capability.reason ?? 'ID numbers cannot be found on this device. Drag over a number to mask it.');
      return;
    }
    setState(() => _autoMasking = true);
    try {
      // Read the page with the masks already placed, so they are not found
      // again.
      final layout = await (engine as OcrLayoutEngine).recognizeLayout(
        page.copyWith(annotations: _marks),
        languageCode: 'en',
      );
      if (!mounted) return;
      final found = const IdNumberFinder().find(layout);
      if (found.isEmpty) {
        say('No ID numbers found. Drag over a number to mask it by hand.');
        return;
      }
      _change([
        ..._marks!,
        for (final m in found)
          MaskAnnotation(id: _newId(), left: m.left, top: m.top, right: m.right, bottom: m.bottom, label: m.kind.label),
      ]);
      final kinds = {for (final m in found) m.kind.label}.join(', ');
      say('Masked ${found.length} ${found.length == 1 ? 'number' : 'numbers'} ($kinds). Check the page before sharing.');
    } catch (_) {
      if (mounted) say('Could not read the page. Drag over a number to mask it by hand.');
    } finally {
      if (mounted) setState(() => _autoMasking = false);
    }
  }

  void _done() {
    ref.read(scanControllerProvider.notifier).setAnnotations(widget.pageId, _marks!);
    Navigator.of(context).pop();
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard your marks?'),
        content: const Text('Your changes to this page have not been saved.'),
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
    final page = ref.watch(scanControllerProvider.select((s) => s.pageById(widget.pageId)));
    if (page == null) return const Scaffold(body: SizedBox.shrink());
    _marks ??= page.annotations;
    _image ??= ref.read(renderServiceProvider).render(page, maxDimension: RenderService.previewSize);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Markup'),
          actions: [
            IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: _dirty ? _undoLast : null),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: FilledButton(onPressed: _done, child: const Text('Done')),
            ),
          ],
        ),
        body: FutureBuilder<RenderedImage>(
          future: _image,
          builder: (context, snap) {
            final image = snap.data;
            if (snap.hasError) return const Center(child: Icon(Icons.broken_image_outlined));
            if (image == null) return const Center(child: CircularProgressIndicator());
            // Only the page's proportions matter to the overlay.
            final editorPage = EditorPage(
              id: page.id,
              sourcePage: 1,
              widthPt: image.width.toDouble(),
              heightPt: image.height.toDouble(),
              annotations: _marks!,
            );
            return Column(
              children: [
                Expanded(
                  child: MarkupCanvas(
                    page: editorPage,
                    image: Image.file(File(image.path), fit: BoxFit.fill, gaplessPlayback: true),
                    tool: _tool,
                    style: _style,
                    zoom: _zoom,
                    callbacks: _callbacks(editorPage),
                  ),
                ),
                MarkupToolbar(
                  tools: EditorTool.values,
                  tool: _tool,
                  onTool: (t) => setState(() => _tool = t),
                  style: _style,
                  onStyle: (v) => setState(() => _style = v),
                  onSignature: () => _addSignature(editorPage),
                  onAutoMask: () => _autoMask(page),
                  autoMaskLocked: !ref.watch(planIncludesProvider(PlanFeature.autoMask)),
                  autoMaskBusy: _autoMasking,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
