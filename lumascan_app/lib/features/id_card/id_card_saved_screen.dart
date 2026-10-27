import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/theme.dart';
import '../../domain/id_copy.dart';
import '../../domain/models.dart';
import '../../ui/compact_action_button.dart';
import '../capture/add_pages_sheet.dart';
import '../export/export_choice.dart';
import '../pages/page_actions.dart';
import '../pages/page_image.dart';
import '../pages/scan_controller.dart';
import '../pdf_editor/open_pdf.dart';
import '../share/send_pdf_sheet.dart';
import 'id_card_review_screen.dart';
import 'id_card_session.dart';

/// The saved copy (ID-08): every page of the document two to a row, the ID
/// copy first as 01, then each side, then the dashed "Tap to add new pages"
/// tile; Add, Collage, Share, Edit PDF and More along the bottom. The sides
/// are kept, so the copy can be made again after a side is changed.
class IdCardSavedScreen extends ConsumerStatefulWidget {
  const IdCardSavedScreen({super.key});

  @override
  ConsumerState<IdCardSavedScreen> createState() => _IdCardSavedScreenState();
}

class _IdCardSavedScreenState extends ConsumerState<IdCardSavedScreen> {
  /// Pages picked for a collage, in the order picked; null when not picking.
  List<String>? _collage;
  bool _working = false;

  IdCopyDraftNotifier get _session => ref.read(idCopyDraftProvider.notifier);

  String _label(IdCopyDraft? draft, ScanPage page) {
    if (draft == null) return '';
    if (page.id == draft.compositeId) return 'ID copy';
    final side = draft.sideIds.indexOf(page.id);
    return side < 0 ? '' : draft.type.sideName(side);
  }

  Future<void> _openPage(ScanPage page, int index) async {
    final collage = _collage;
    if (collage != null) {
      setState(() {
        if (collage.contains(page.id)) {
          collage.remove(page.id);
        } else if (collage.length < maxCollagePictures) {
          collage.add(page.id);
        } else {
          _snack('A collage holds up to $maxCollagePictures pages.');
        }
      });
      return;
    }
    // The copy opens its review, where a change makes it again.
    if (page.id == ref.read(idCopyDraftProvider)?.compositeId) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const IdCardReviewScreen(fromSaved: true)));
      return;
    }
    await showPageActions(context, ref, page, index);
  }

  Future<void> _makeCollage() async {
    final picked = _collage;
    if (picked == null || picked.length < 2) {
      _snack('Pick at least 2 pages for the collage.');
      return;
    }
    final scan = ref.read(scanControllerProvider);
    final pages = [for (final id in picked) ?scan.pageById(id)];
    await _busy(() async {
      await _session.makeCollagePage(pages, paper: ref.read(idCopyDraftProvider)?.paper ?? PdfPageSize.a4);
      if (mounted) setState(() => _collage = null);
      _snack('Collage added as the last page.');
    });
  }

  Future<File?> _savePdf({List<ScanPage>? only}) async {
    File? file;
    await _busy(() async => file = await _session.savePdf(only: only));
    return file;
  }

  Future<void> _share() async {
    final scan = ref.read(scanControllerProvider);
    final copy = scan.pageById(ref.read(idCopyDraftProvider)?.compositeId ?? '');
    var only = false;
    if (copy != null && scan.pages.length > 1) {
      final choice = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('ID copy page'),
                subtitle: const Text('One page, ready to print'),
                onTap: () => Navigator.pop(sheet, true),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text('All ${scan.pages.length} pages'),
                subtitle: const Text('The copy and each side'),
                onTap: () => Navigator.pop(sheet, false),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      only = choice;
    }
    final file = await _savePdf(only: only ? [copy!] : null);
    if (file == null || !mounted) return;
    await showSendPdfSheet(
      context,
      pdfPath: file.path,
      name: file.uri.pathSegments.last,
      pageCount: only ? 1 : scan.pages.length,
    );
  }

  Future<void> _editPdf() async {
    final file = await _savePdf();
    if (file == null || !mounted) return;
    await openPdfInEditor(context, ref, path: file.path, name: ref.read(scanControllerProvider).info?.name ?? 'ID card');
  }

  Future<void> _more() async {
    final action = await showModalBottomSheet<_More>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in _More.values)
              ListTile(leading: Icon(m.icon), title: Text(m.label), onTap: () => Navigator.pop(sheet, m)),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _More.export:
        await showExportChoice(context, ref);
      case _More.pages:
        openDraft(context);
      case _More.rename:
        final name = ref.read(scanControllerProvider).info?.name ?? '';
        final next = await showDialog<String>(context: context, builder: (_) => _RenameDialog(initial: name));
        if (next != null) ref.read(scanControllerProvider.notifier).rename(next);
      case _More.home:
        await saveAndGoHome(context, ref);
    }
  }

  Future<void> _busy(Future<void> Function() run) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await run();
    } on Object catch (e) {
      debugPrint('ID copy action failed: $e');
      _snack('That did not work. Your pages are unchanged.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final draft = ref.watch(idCopyDraftProvider);
    final pages = scan.pages;
    final collage = _collage;
    final c = LumaColors.of(context);
    return PopScope(
      canPop: collage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _collage = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: collage != null
              ? Text('Pick pages (${collage.length} of $maxCollagePictures)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(scan.info?.name ?? 'ID card', maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${scan.exported ? 'Saved to your Library · ' : ''}'
                      '${pages.length} page${pages.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
          actions: [
            if (collage != null) ...[
              TextButton(onPressed: () => setState(() => _collage = null), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: LumaColors.scan, foregroundColor: LumaColors.onScan),
                onPressed: _working ? null : _makeCollage,
                child: const Text('Make'),
              ),
              const SizedBox(width: Space.sm),
            ],
          ],
        ),
        body: Stack(
          children: [
            GridView.builder(
              padding: const EdgeInsets.all(Space.lg),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: Space.lg,
                crossAxisSpacing: Space.lg,
                childAspectRatio: 0.66,
              ),
              itemCount: pages.length + 1,
              itemBuilder: (context, i) {
                if (i == pages.length) {
                  return _AddTile(onTap: () => showAddPagesSheet(context, ref));
                }
                final page = pages[i];
                final pick = collage?.indexOf(page.id) ?? -1;
                return _PageTile(
                  page: page,
                  number: (i + 1).toString().padLeft(2, '0'),
                  label: _label(draft, page),
                  picking: collage != null,
                  pickNumber: pick < 0 ? null : pick + 1,
                  onTap: () => _openPage(page, i),
                );
              },
            ),
            if (_working)
              const Positioned.fill(
                child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator())),
              ),
          ],
        ),
        bottomNavigationBar: Material(
          color: c.surface,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                for (final (icon, label, run) in <(IconData, String, VoidCallback)>[
                  (Icons.add_photo_alternate_outlined, 'Add', () => showAddPagesSheet(context, ref)),
                  (Icons.dashboard_outlined, 'Collage', () => setState(() => _collage = [])),
                  (Icons.ios_share, 'Share', _share),
                  (Icons.edit_document, 'Edit PDF', _editPdf),
                  (Icons.more_horiz, 'More', _more),
                ])
                  Expanded(
                    child: CompactActionButton(
                      icon: icon,
                      label: label,
                      enabled: !_working && collage == null,
                      onPressed: _working || collage != null ? null : run,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _More {
  export(Icons.download_outlined, 'Save as PDF, Word or JPG'),
  pages(Icons.view_agenda_outlined, 'Open all pages'),
  rename(Icons.drive_file_rename_outline, 'Rename'),
  home(Icons.home_outlined, 'Done');

  const _More(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.number,
    required this.label,
    required this.picking,
    required this.pickNumber,
    required this.onTap,
  });

  final ScanPage page;
  final String number;
  final String label;
  final bool picking;
  final int? pickNumber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final picked = pickNumber != null;
    return Semantics(
      button: true,
      selected: picked,
      label: 'Page $number${label.isEmpty ? '' : ', $label'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: picked ? LumaColors.scan : c.line, width: picked ? 3 : 1),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(padding: const EdgeInsets.all(4), child: PageImage(page: page)),
                    if (picking)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: picked ? LumaColors.scan : Colors.white,
                          child: picked
                              ? Text('$pickNumber', style: const TextStyle(color: Colors.white, fontSize: 13))
                              : const Icon(Icons.circle_outlined, size: 22, color: Colors.black45),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(number, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (label.isNotEmpty) Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted)),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    return Semantics(
      button: true,
      label: 'Tap to add new pages',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorder(c.muted),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 36, color: c.muted),
                const SizedBox(height: Space.xs),
                Text('Tap to add new pages', textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 6.0, gap = 4.0;
    void line(Offset a, Offset b) {
      final length = (b - a).distance;
      final dir = (b - a) / length;
      for (var d = 0.0; d < length; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, length), paint);
      }
    }

    final r = (Offset.zero & size).deflate(1);
    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename'),
    content: TextField(controller: _text, autofocus: true, maxLength: 80),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('OK')),
    ],
  );
}
