import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferences.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import '../../domain/signature_library.dart';
import '../../pdf_edit/annotations.dart';
import '../../ui/state_views.dart';
import '../../ui/upgrade_dialog.dart';
import '../markup/markup_actions.dart';
import '../pdf_editor/annotation_layer.dart';
import '../pdf_editor/signature_pad_screen.dart';
import 'signature_library_controller.dart';
import '../../ui/luma_icons.dart';

/// Ink colour of signatures and stamps.
const signatureInk = 0xFF14213D;

/// What was picked in the Sign sheet.
sealed class SignChoice {
  const SignChoice();
}

class DrawChoice extends SignChoice {
  const DrawChoice(this.kind);

  final SignatureKind kind;
}

class SavedChoice extends SignChoice {
  const SavedChoice(this.signature);

  final SavedSignature signature;
}

class StampChoice extends SignChoice {
  const StampChoice(this.kind);

  final StampKind kind;
}

/// A Pro row tapped on a plan without the signature library.
class LockedChoice extends SignChoice {
  const LockedChoice();
}

/// Opens the Sign sheet and returns the mark to add to a page whose
/// width/height ratio is [pageAspect]: a new drawing, a saved signature or
/// initials, or a date or name stamp. Returns null when cancelled.
Future<Annotation?> chooseSignatureOrStamp(
  BuildContext context,
  WidgetRef ref, {
  required String Function() newId,
  required double pageAspect,
  DateTime Function() now = DateTime.now,
}) async {
  final choice = await showModalBottomSheet<SignChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SignSheet(today: now()),
  );
  if (choice == null || !context.mounted) return null;
  final library = ref.read(signatureLibraryProvider.notifier);
  switch (choice) {
    case LockedChoice():
      await showUpgradeDialog(context, PlanFeature.signatureLibrary, what: 'The signature library');
      return null;
    case DrawChoice(:final kind):
      final unlocked = ref.read(planIncludesProvider(PlanFeature.signatureLibrary));
      final drawn = await SignaturePadScreen.show(context, kind: kind, offerSave: unlocked);
      if (drawn == null) return null;
      final signature = SignatureAnnotation.fromPadStrokes(
        id: newId(),
        strokes: drawn.strokes,
        color: signatureInk,
        pageAspect: pageAspect,
        width: kind.placedWidth,
      );
      if (signature != null && drawn.save) {
        library.save(
          SavedSignature(
            id: newId(),
            kind: kind,
            strokes: signature.strokes,
            aspectRatio: signature.aspectRatio,
            createdAt: now(),
          ),
        );
      }
      return signature;
    case SavedChoice(:final signature):
      return SignatureAnnotation.centred(
        id: newId(),
        strokes: signature.strokes,
        aspectRatio: signature.aspectRatio,
        color: signatureInk,
        pageAspect: pageAspect,
        width: signature.kind.placedWidth,
      );
    case StampChoice(:final kind):
      var name = ref.read(signatureLibraryProvider).stampName;
      if (kind.needsName && name.isEmpty) {
        final typed = await askStampName(context);
        if (typed == null || typed.trim().isEmpty) return null;
        library.setStampName(typed);
        name = typed.trim();
      }
      return TextAnnotation(
        id: newId(),
        origin: const NormPoint(0.35, 0.45),
        text: kind.text(name: name, day: now()),
        color: signatureInk,
        fontSize: 0.03,
      );
  }
}

/// Asks for the name the name stamp writes.
Future<String?> askStampName(BuildContext context, {String initial = ''}) =>
    askAnnotationText(context, title: 'Name for the stamp', initial: initial);

/// The Sign sheet: saved signatures and initials to place with a tap, draw
/// a new one, and date and name stamps. On a plan without the signature
/// library only drawing a signature works; the rest shows a Pro badge.
class SignSheet extends ConsumerWidget {
  const SignSheet({super.key, required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(planIncludesProvider(PlanFeature.signatureLibrary));
    final library = ref.watch(signatureLibraryProvider);
    final text = Theme.of(context).textTheme;
    // Drawing a one-off signature works on every plan.
    bool free(SignChoice c) => c is DrawChoice && c.kind == SignatureKind.signature;
    void pick(SignChoice c) => Navigator.pop(context, unlocked || free(c) ? c : const LockedChoice());
    final badge = unlocked ? null : const PremiumBadge(label: 'Pro');
    final saved = unlocked ? library.signatures : const <SavedSignature>[];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Sign', style: text.titleLarge)),
                  ?badge,
                ],
              ),
            ),
            if (saved.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Saved', style: text.titleSmall),
              ),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: saved.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _SavedTile(
                    signature: saved[i],
                    onTap: () => pick(SavedChoice(saved[i])),
                    onDelete: () => ref.read(signatureLibraryProvider.notifier).remove(saved[i].id),
                  ),
                ),
              ),
            ] else if (!unlocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'With Pro, signatures and initials are saved so you can place them again with one tap.',
                  style: text.bodySmall,
                ),
              ),
            ListTile(
              leading: const Icon(LumaIcons.sign),
              title: const Text('Draw a new signature'),
              subtitle: unlocked ? const Text('Saved for next time unless you switch it off') : null,
              onTap: () => pick(const DrawChoice(SignatureKind.signature)),
            ),
            ListTile(
              leading: const Icon(LumaIcons.initials),
              title: const Text('Draw initials'),
              trailing: badge,
              onTap: () => pick(const DrawChoice(SignatureKind.initials)),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text('Stamps', style: text.titleSmall),
            ),
            ListTile(
              leading: const Icon(LumaIcons.date),
              title: const Text('Date stamp'),
              subtitle: Text(stampDate(today)),
              trailing: badge,
              onTap: () => pick(const StampChoice(StampKind.date)),
            ),
            ListTile(
              leading: const Icon(LumaIcons.idCard),
              title: const Text('Name stamp'),
              subtitle: Text(library.stampName.isEmpty || !unlocked ? 'Your name, typed once' : library.stampName),
              trailing:
                  badge ??
                  (library.stampName.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Change name',
                          icon: const Icon(LumaIcons.rename),
                          onPressed: () async {
                            final typed = await askStampName(context, initial: library.stampName);
                            if (typed != null && typed.trim().isNotEmpty) {
                              ref.read(signatureLibraryProvider.notifier).setStampName(typed);
                            }
                          },
                        )),
              onTap: () => pick(const StampChoice(StampKind.name)),
            ),
            ListTile(
              leading: const Icon(LumaIcons.nameAndDate),
              title: const Text('Name and date'),
              trailing: badge,
              onTap: () => pick(const StampChoice(StampKind.nameAndDate)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved signature or initials: tap to place, the cross to delete.
class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.signature, required this.onTap, required this.onDelete});

  final SavedSignature signature;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = SignatureAnnotation(
      id: signature.id,
      strokes: signature.strokes,
      left: 0,
      top: 0,
      width: 1,
      aspectRatio: signature.aspectRatio,
      color: signatureInk,
    );
    return Semantics(
      button: true,
      label: 'Place saved ${signature.kind.label.toLowerCase()}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('saved:${signature.id}'),
          onTap: onTap,
          child: SizedBox(
            width: 140,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: signature.aspectRatio,
                      child: CustomPaint(painter: SignaturePainter(preview)),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 6,
                  child: Text(
                    signature.kind.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.black54),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton(
                    tooltip: 'Delete saved ${signature.kind.label.toLowerCase()}',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(LumaIcons.close, size: 18, color: Colors.black54),
                    onPressed: onDelete,
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
