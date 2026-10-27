import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/theme.dart';
import '../../domain/id_copy.dart';
import '../../domain/models.dart';
import '../../imaging/id_copy_composer.dart';
import '../crop/crop_screen.dart';
import '../filters/filter_screen.dart';
import '../markup/markup_screen.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';
import '../pdf_editor/annotation_layer.dart';
import 'id_card_capture_screen.dart';
import 'id_card_saved_screen.dart';
import 'id_card_session.dart';

/// Review the copy (ID-06): a black header with Back, the two-line title
/// and Help; the white A4 page with every side where it will print, and
/// page number 01; the paper and size; and Add Watermark, Edit, Filter and
/// the green ✓ along the bottom. Tapping a side picks it for Edit and Filter
/// and opens Edit.
class IdCardReviewScreen extends ConsumerStatefulWidget {
  const IdCardReviewScreen({super.key, this.fromSaved = false});

  /// Opened from the saved grid: ✓ goes back to it instead of opening another.
  final bool fromSaved;

  @override
  ConsumerState<IdCardReviewScreen> createState() => _IdCardReviewScreenState();
}

class _IdCardReviewScreenState extends ConsumerState<IdCardReviewScreen> {
  int _selected = 0;
  bool _saving = false;

  IdCopyDraftNotifier get _session => ref.read(idCopyDraftProvider.notifier);

  ScanPage? _selectedPage() {
    final draft = ref.read(idCopyDraftProvider);
    if (draft == null) return null;
    final sides = sidePages(draft, ref.read(scanControllerProvider));
    return _selected < sides.length ? sides[_selected] : null;
  }

  Future<void> _rename(String current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: 'Rename', initial: current, hint: 'Name'),
    );
    if (name != null) ref.read(scanControllerProvider.notifier).rename(name);
  }

  Future<void> _watermark() async {
    final draft = ref.read(idCopyDraftProvider);
    if (draft == null) return;
    final result = await showDialog<_WatermarkResult>(
      context: context,
      builder: (_) => AddWatermarkDialog(initial: draft.watermark),
    );
    if (result == null) return;
    _session.update((d) => d.withWatermark(result.text));
  }

  Future<void> _edit() async {
    final page = _selectedPage();
    final draft = ref.read(idCopyDraftProvider);
    if (draft == null) return;
    if (page == null) return _retake(_selected);
    final action = await showModalBottomSheet<_EditAction>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
              child: Text(draft.type.sideName(_selected), style: Theme.of(sheet).textTheme.titleLarge),
            ),
            for (final a in _EditAction.values)
              if (a != _EditAction.swap || draft.type.sides > 1)
                ListTile(
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  subtitle: a.hint == null ? null : Text(a.hint!),
                  onTap: () => Navigator.pop(sheet, a),
                ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final controller = ref.read(scanControllerProvider.notifier);
    final navigator = Navigator.of(context);
    switch (action) {
      case _EditAction.crop:
        await navigator.push(MaterialPageRoute<void>(builder: (_) => CropScreen(pageId: page.id)));
      case _EditAction.rotate:
        controller.rotate(page.id);
      case _EditAction.mask:
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => MarkupScreen(pageId: page.id, initialTool: EditorTool.mask),
          ),
        );
      case _EditAction.retake:
        await _retake(_selected);
      case _EditAction.swap:
        _session.update((d) => d.swapped());
    }
  }

  Future<void> _retake(int side) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => IdCardCaptureScreen(retakeSide: side)));

  Future<void> _filter() async {
    final page = _selectedPage();
    if (page == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilterScreen(pageId: page.id)));
  }

  Future<void> _done() async {
    if (_saving) return;
    final draft = ref.read(idCopyDraftProvider);
    if (draft == null) return;
    final sides = sidePages(draft, ref.read(scanControllerProvider));
    final missing = sides.indexWhere((s) => s == null);
    if (missing >= 0) {
      _snack(
        draft.type.sides > 1
            ? 'Capture the ${draft.type.sideName(missing).toLowerCase()} to build a two-sided copy.'
            : 'Capture the ${draft.type.sideName(missing).toLowerCase()} first.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _session.makeCopyPage();
      await _session.savePdf();
      if (!mounted) return;
      if (widget.fromSaved) {
        Navigator.of(context).pop();
      } else {
        await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const IdCardSavedScreen()));
      }
    } on Object catch (e) {
      debugPrint('ID copy save failed: $e');
      if (mounted) _snack('We kept your draft. Finish saving when you are ready.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Making an ID copy'),
      content: const Text(
        'Tap a side to crop, resize, rotate or take it again, or to hide a number with a mask.\n\n'
        'Filter makes the selected side clearer. Add Watermark prints a purpose, such as '
        '"For bank KYC only", across every side so the copy is less useful anywhere else.\n\n'
        'The copy is made and kept on this phone. $appName copies your card; it does not check or verify it.',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(idCopyDraftProvider);
    final scan = ref.watch(scanControllerProvider);
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing to review')),
      );
    }
    final sides = sidePages(draft, scan);
    final name = scan.info?.name ?? 'ID card';
    const bar = Colors.black;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFE4E4E4),
        appBar: AppBar(
          backgroundColor: bar,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Semantics(
            button: true,
            hint: 'Rename',
            child: InkWell(
              onTap: () => _rename(name),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Tap the title above to rename; tap the picture to crop or rotate',
                    maxLines: 2,
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          actions: [IconButton(tooltip: 'Help', icon: const Icon(Icons.help_outline), onPressed: _help)],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: IdCopyPagePreview(
                      draft: draft,
                      sides: sides,
                      selected: _selected,
                      onTapSide: (i) {
                        setState(() => _selected = i);
                        _edit();
                      },
                    ),
                  ),
                ),
              ),
              _LayoutRow(
                draft: draft,
                onPaper: (paper) => _session.update((d) => d.withLayout(paper: paper)),
                onScale: (scale) => _session.update((d) => d.withLayout(scale: scale)),
              ),
              _Toolbar(
                saving: _saving,
                hasWatermark: draft.watermark != null,
                onWatermark: _watermark,
                onEdit: _edit,
                onFilter: _filter,
                onDone: _done,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _EditAction {
  crop(Icons.crop, 'Crop or resize', 'Move the corners to fit the card'),
  rotate(Icons.rotate_right, 'Rotate', 'A quarter turn to the right'),
  mask(Icons.visibility_off_outlined, 'Hide a number', 'Draw a mask over your Aadhaar or any number'),
  retake(Icons.photo_camera_outlined, 'Retake', null),
  swap(Icons.swap_vert, 'Swap front and back', null);

  const _EditAction(this.icon, this.label, this.hint);

  final IconData icon;
  final String label;
  final String? hint;
}

/// The A4 page as it will print: white paper, each side in its place (or a
/// prompt to take it), the watermark drawn the same way the saved page
/// draws it, and the page number.
class IdCopyPagePreview extends StatelessWidget {
  const IdCopyPagePreview({
    super.key,
    required this.draft,
    required this.sides,
    required this.selected,
    required this.onTapSide,
  });

  final IdCopyDraft draft;
  final List<ScanPage?> sides;
  final int selected;
  final ValueChanged<int> onTapSide;

  @override
  Widget build(BuildContext context) {
    final paper = paperSizeMm(draft.paper);
    final slots = idCopySlots(draft.type, paper: draft.paper, scale: draft.scale);
    return AspectRatio(
      aspectRatio: paper.width / paper.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            Rect place(Rect s) => Rect.fromLTWH(
              s.left * box.maxWidth,
              s.top * box.maxHeight,
              s.width * box.maxWidth,
              s.height * box.maxHeight,
            );
            return Stack(
              children: [
                for (var i = 0; i < slots.length; i++)
                  Positioned.fromRect(
                    rect: place(slots[i]),
                    child: _SideSlot(
                      name: draft.type.sideName(i),
                      page: i < sides.length ? sides[i] : null,
                      selected: i == selected,
                      watermark: draft.watermark,
                      onTap: () => onTapSide(i),
                    ),
                  ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Text(
                    '01',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF555555), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SideSlot extends StatelessWidget {
  const _SideSlot({
    required this.name,
    required this.page,
    required this.selected,
    required this.watermark,
    required this.onTap,
  });

  final String name;
  final ScanPage? page;
  final bool selected;
  final String? watermark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final page = this.page;
    return Semantics(
      button: true,
      selected: selected,
      label: page == null ? '$name not taken. Take it' : '$name. Edit',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: selected ? LumaColors.scan : Colors.transparent, width: 2),
          ),
          child: page == null
              ? Container(
                  color: const Color(0xFFF2F2F2),
                  alignment: Alignment.center,
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          const Icon(Icons.add_a_photo_outlined, color: Colors.black54),
                          Text('Take the ${name.toLowerCase()}', style: const TextStyle(color: Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    PageImage(page: page, maxDimension: 1600),
                    if (watermark != null) IgnorePointer(child: CustomPaint(painter: _WatermarkPainter(watermark!))),
                  ],
                ),
        ),
      ),
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  _WatermarkPainter(this.text);

  final String text;

  @override
  void paint(Canvas canvas, Size size) => paintWatermark(canvas, Offset.zero & size, text);

  @override
  bool shouldRepaint(_WatermarkPainter old) => old.text != text;
}

class _LayoutRow extends StatelessWidget {
  const _LayoutRow({required this.draft, required this.onPaper, required this.onScale});

  final IdCopyDraft draft;
  final ValueChanged<PdfPageSize> onPaper;
  final ValueChanged<IdCopyScale> onScale;

  @override
  Widget build(BuildContext context) {
    final style = SegmentedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      selectedBackgroundColor: LumaColors.scan,
      selectedForegroundColor: LumaColors.onScan,
      visualDensity: VisualDensity.compact,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Space.md,
        runSpacing: Space.sm,
        children: [
          SegmentedButton<PdfPageSize>(
            style: style,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PdfPageSize.a4, label: Text('A4')),
              ButtonSegment(value: PdfPageSize.letter, label: Text('Letter')),
            ],
            selected: {draft.paper},
            onSelectionChanged: (s) => onPaper(s.first),
          ),
          SegmentedButton<IdCopyScale>(
            style: style,
            showSelectedIcon: false,
            segments: [for (final s in IdCopyScale.values) ButtonSegment(value: s, label: Text(s.label))],
            selected: {draft.scale},
            onSelectionChanged: (s) => onScale(s.first),
          ),
        ],
      ),
    );
  }
}

/// Add Watermark, Edit, Filter and the green ✓, in that order, white on black.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.saving,
    required this.hasWatermark,
    required this.onWatermark,
    required this.onEdit,
    required this.onFilter,
    required this.onDone,
  });

  final bool saving;
  final bool hasWatermark;
  final VoidCallback onWatermark;
  final VoidCallback onEdit;
  final VoidCallback onFilter;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    Widget tool(IconData icon, String label, VoidCallback onTap, {String? semantics}) => Expanded(
      child: Semantics(
        button: true,
        label: semantics ?? label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: saving ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(height: 2),
                Text(label, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.sm),
      child: Row(
        children: [
          tool(
            hasWatermark ? Icons.branding_watermark : Icons.branding_watermark_outlined,
            'Add Watermark',
            onWatermark,
          ),
          tool(Icons.crop_rotate, 'Edit', onEdit, semantics: 'Edit: crop, resize or rotate the selected side'),
          tool(Icons.auto_fix_high_outlined, 'Filter', onFilter),
          Expanded(
            child: Center(
              child: Semantics(
                button: true,
                label: 'Save the copy',
                excludeSemantics: true,
                child: InkResponse(
                  onTap: saving ? null : onDone,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: LumaColors.scan, shape: BoxShape.circle),
                    child: saving
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          )
                        : const Icon(Icons.check, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatermarkResult {
  const _WatermarkResult(this.text);

  /// Null removes the watermark.
  final String? text;
}

/// Add Watermark (ID-07): the placeholder "Enter the content for the
/// watermark" over a green underline, then Cancel and OK at the lower right.
/// An empty purpose is not saved silently: OK explains what to do. With a
/// watermark already set, Remove takes it off.
class AddWatermarkDialog extends StatefulWidget {
  const AddWatermarkDialog({super.key, this.initial});

  final String? initial;

  @override
  State<AddWatermarkDialog> createState() => _AddWatermarkDialogState();
}

class _AddWatermarkDialogState extends State<AddWatermarkDialog> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _ok() {
    final error = validateWatermark(_text.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _WatermarkResult(_text.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    const green = UnderlineInputBorder(borderSide: BorderSide(color: LumaColors.scan, width: 2));
    return AlertDialog(
      title: const Text('Add Watermark'),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: maxWatermarkLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _ok(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          hintText: 'Enter the content for the watermark',
          errorText: _error,
          enabledBorder: green,
          focusedBorder: green,
          border: green,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
        ),
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _WatermarkResult(null)),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: _ok,
          child: const Text(
            'OK',
            style: TextStyle(color: LumaColors.scan, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.hint});

  final String title;
  final String initial;
  final String hint;

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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLength: 80,
      decoration: InputDecoration(hintText: widget.hint),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('OK')),
    ],
  );
}
