import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/theme.dart';
import '../../domain/id_copy.dart';
import '../../domain/models.dart';
import '../pages/scan_controller.dart';
import 'id_card_capture_screen.dart';
import 'id_card_session.dart';
import '../../ui/luma_icons.dart';

/// Opens ID card mode at the type picker (ID-01: the Tools and Create
/// shortcut goes here, never to the plain document camera).
Future<void> openIdCardStudio(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const IdCardTypeScreen()));

/// Choose what to copy (ID-02 to ID-04): an A4 example of the result, a line
/// on what it makes, Make it now, then Single Side, ID Card and Passport.
/// Picking a type only moves the green border and changes the example;
/// every other control stays where it is.
class IdCardTypeScreen extends ConsumerStatefulWidget {
  const IdCardTypeScreen({super.key});

  @override
  ConsumerState<IdCardTypeScreen> createState() => _IdCardTypeScreenState();
}

class _IdCardTypeScreenState extends ConsumerState<IdCardTypeScreen> {
  IdCopyType _type = IdCopyType.idCard;
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    // The copy is a document of its own; whatever was on screen is kept on Home.
    await ref.read(scanControllerProvider.notifier).startNewDocument();
    ref.read(idCopyDraftProvider.notifier).start(_type);
    if (!mounted) return;
    setState(() => _starting = false);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const IdCardCaptureScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('ID Card')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.sm, Space.page, Space.xl),
          children: [
            Semantics(header: true, child: Text('A4 paper example', style: text.titleMedium)),
            const SizedBox(height: Space.md),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Semantics(
                  label: 'Example: ${_type.description}',
                  excludeSemantics: true,
                  child: IdCopyExample(type: _type),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            // As tall as the longest description, so nothing below moves
            // when the type changes (ID-03, ID-04).
            Stack(
              alignment: Alignment.topCenter,
              children: [
                for (final type in IdCopyType.values)
                  Visibility(
                    visible: type == _type,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(
                      type.description,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: c.muted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Made on this phone. $appName copies your card; it does not check or verify it.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LumaColors.scan,
                foregroundColor: LumaColors.onScan,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _starting ? null : _start,
              child: const Text('Make it now'),
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                for (final type in IdCopyType.values) ...[
                  if (type != IdCopyType.values.first) const SizedBox(width: Space.md),
                  Expanded(
                    child: _TypeChoice(
                      key: ValueKey('id-type-${type.id}'),
                      type: type,
                      selected: type == _type,
                      onTap: () => setState(() => _type = type),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChoice extends StatelessWidget {
  const _TypeChoice({super.key, required this.type, required this.selected, required this.onTap});

  final IdCopyType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LumaColors.of(context);
    final icon = switch (type) {
      IdCopyType.singleSide => LumaIcons.creditCard,
      IdCopyType.idCard => LumaIcons.idCard,
      IdCopyType.passport => LumaIcons.book,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: type.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.xs),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: selected ? LumaColors.scan : c.line, width: selected ? 2.5 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? LumaColors.scan : c.muted, size: 28),
              const SizedBox(height: Space.xs),
              Text(
                type.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white sheet of paper with made-up sample documents where the real ones
/// will go, laid out exactly as the copy will be. No real card artwork.
class IdCopyExample extends StatelessWidget {
  const IdCopyExample({super.key, required this.type});

  final IdCopyType type;

  @override
  Widget build(BuildContext context) {
    final paper = paperSizeMm(PdfPageSize.a4);
    return AspectRatio(
      aspectRatio: paper.width / paper.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD0D0D0)),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final slots = idCopySlots(type);
            return Stack(
              children: [
                for (var i = 0; i < slots.length; i++)
                  Positioned(
                    left: slots[i].left * box.maxWidth,
                    top: slots[i].top * box.maxHeight,
                    width: slots[i].width * box.maxWidth,
                    height: slots[i].height * box.maxHeight,
                    child: _SampleDocument(back: i == 1, passport: type == IdCopyType.passport),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SampleDocument extends StatelessWidget {
  const _SampleDocument({required this.back, required this.passport});

  final bool back;
  final bool passport;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF9AA6B2);
    Widget line(double width) => FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: Container(height: 3, margin: const EdgeInsets.symmetric(vertical: 1.5), color: ink),
    );
    final lines = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [line(0.9), line(0.7), line(0.8), line(0.5)],
    );
    final photo = AspectRatio(
      aspectRatio: 0.8,
      child: Container(
        color: const Color(0xFFDCE3EA),
        child: const FittedBox(child: Icon(LumaIcons.profile, color: ink)),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F7),
        borderRadius: BorderRadius.circular(passport ? 2 : 4),
        border: Border.all(color: const Color(0xFFB8C2CC)),
      ),
      child: Stack(
        children: [
          if (passport)
            Column(
              children: [
                Expanded(child: lines),
                const Divider(height: 4, color: ink),
                Expanded(
                  child: Row(
                    children: [
                      photo,
                      const SizedBox(width: 4),
                      Expanded(child: lines),
                    ],
                  ),
                ),
              ],
            )
          else if (back)
            Row(
              children: [
                Expanded(child: lines),
                const SizedBox(width: 4),
                const AspectRatio(aspectRatio: 1, child: ColoredBox(color: Color(0xFFDCE3EA))),
              ],
            )
          else
            Row(
              children: [
                photo,
                const SizedBox(width: 4),
                Expanded(child: lines),
              ],
            ),
          const Align(
            alignment: Alignment.topRight,
            child: Text(
              'SAMPLE',
              style: TextStyle(fontSize: 6, fontWeight: FontWeight.w800, color: Color(0xFFB0413E)),
            ),
          ),
        ],
      ),
    );
  }
}
