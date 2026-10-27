import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/domain/plan.dart';
import 'package:lumascan/domain/signature_library.dart';
import 'package:lumascan/features/pdf_editor/pdf_editor_screen.dart';
import 'package:lumascan/features/signatures/signature_library_controller.dart';
import 'package:lumascan/pdf_edit/annotations.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:signature/signature.dart';

import 'support/memory_stores.dart';

SavedSignature saved(String id, {SignatureKind kind = SignatureKind.signature}) => SavedSignature(
  id: id,
  kind: kind,
  strokes: const [
    [NormPoint(0, 0.5), NormPoint(0.5, 0.2), NormPoint(1, 0.8)],
  ],
  aspectRatio: 3,
  createdAt: DateTime(2026, 10, 27),
);

/// The saved signatures and initials shown in the Sign sheet.
final savedTile = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('saved:'));

void main() {
  test('Pro and Gold include the signature library; Basic does not', () {
    expect(AppPlan.basic.includes(PlanFeature.signatureLibrary), isFalse);
    expect(AppPlan.pro.includes(PlanFeature.signatureLibrary), isTrue);
    expect(AppPlan.gold.includes(PlanFeature.signatureLibrary), isTrue);
  });

  test('the library survives a round trip and skips a damaged mark', () {
    final library = const SignatureLibrary(stampName: 'Varun').withSaved(saved('a')).withSaved(
      saved('b', kind: SignatureKind.initials),
    );
    final json = jsonDecode(jsonEncode(library.toJson())) as Map<String, Object?>;
    (json['signatures']! as List).add({'id': 'broken'});
    final back = SignatureLibrary.fromJson(json);
    expect(back.stampName, 'Varun');
    expect(back.signatures.map((s) => s.id), ['b', 'a'], reason: 'newest first, damaged one skipped');
    expect(back.signatures.first.kind, SignatureKind.initials);
    expect(back.signatures.last.strokes, saved('a').strokes);
    expect(back.signatures.last.aspectRatio, 3);
  });

  test('the library keeps at most twelve marks, dropping the oldest', () {
    var library = const SignatureLibrary();
    for (var i = 0; i < SignatureLibrary.maxSaved + 3; i++) {
      library = library.withSaved(saved('$i'));
    }
    expect(library.signatures, hasLength(SignatureLibrary.maxSaved));
    expect(library.signatures.first.id, '${SignatureLibrary.maxSaved + 2}');
    expect(library.without('14').signatures.any((s) => s.id == '14'), isFalse);
  });

  test('stamps write the date with the month as a word', () {
    final day = DateTime(2026, 3, 5);
    expect(stampDate(day), '5 Mar 2026');
    expect(StampKind.date.text(name: 'Varun', day: day), '5 Mar 2026');
    expect(StampKind.name.text(name: ' Varun ', day: day), 'Varun');
    expect(StampKind.nameAndDate.text(name: 'Varun', day: day), 'Varun\n5 Mar 2026');
  });

  test('a saved signature is placed centred at its kind\'s width', () {
    final s = saved('a', kind: SignatureKind.initials);
    final placed = SignatureAnnotation.centred(
      id: 'x',
      strokes: s.strokes,
      aspectRatio: s.aspectRatio,
      color: 0xFF000000,
      pageAspect: 612 / 792,
      width: s.kind.placedWidth,
    );
    expect(placed.width, 0.15);
    expect(placed.left, closeTo(0.425, 1e-9));
    expect(placed.top + placed.heightOn(612 / 792) / 2, closeTo(0.5, 1e-9));
    expect(placed.strokes, s.strokes);
  });

  group('Sign sheet in the PDF editor', () {
    late ProviderContainer container;
    late MemorySignatureLibraryStore store;

    List<Annotation> marks() => container.read(pdfEditControllerProvider).pages.first.annotations;

    Future<void> pumpEditor(WidgetTester tester, {AppPlan plan = AppPlan.pro, SignatureLibrary? library}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      store = MemorySignatureLibraryStore(library ?? const SignatureLibrary());
      container = ProviderContainer(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
          signatureLibraryStoreProvider.overrideWithValue(store),
          planProvider.overrideWithValue(plan),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(pdfEditControllerProvider.notifier)
          .open(path: '/tmp/source.pdf', name: 'Lease.pdf', pageSizes: const [(612, 792)]);
      container.read(signatureLibraryProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PdfEditorScreen(
              pageImage: (page, {thumbnail = false}) => const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Sign'));
      await tester.tap(find.text('Sign'));
      await tester.pumpAndSettle();
    }

    testWidgets('a drawn signature is saved and can be placed again with one tap', (tester) async {
      await pumpEditor(tester);
      await openSheet(tester);
      await tester.tap(find.text('Draw a new signature'));
      await tester.pumpAndSettle();
      expect(find.text('Save for next time'), findsOneWidget);
      await tester.drag(find.byType(Signature), const Offset(120, 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(marks().single, isA<SignatureAnnotation>());
      final library = container.read(signatureLibraryProvider);
      expect(library.signatures, hasLength(1));
      await container.read(signatureLibraryProvider.notifier).settled;
      expect(store.library.signatures, hasLength(1), reason: 'written to the device');

      await openSheet(tester);
      await tester.tap(savedTile);
      await tester.pumpAndSettle();
      expect(marks(), hasLength(2));
      final again = marks().last as SignatureAnnotation;
      expect(again.strokes, library.signatures.single.strokes);
      expect(again.width, SignatureKind.signature.placedWidth);
    });

    testWidgets('initials can be drawn without saving them', (tester) async {
      await pumpEditor(tester);
      await openSheet(tester);
      await tester.tap(find.text('Draw initials'));
      await tester.pumpAndSettle();
      expect(find.text('Draw your initials'), findsOneWidget);
      await tester.tap(find.text('Save for next time'));
      await tester.drag(find.byType(Signature), const Offset(60, 20));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect((marks().single as SignatureAnnotation).width, SignatureKind.initials.placedWidth);
      expect(container.read(signatureLibraryProvider).signatures, isEmpty);
    });

    testWidgets('a saved mark can be deleted from the sheet', (tester) async {
      await pumpEditor(tester, library: SignatureLibrary(signatures: [saved('a')]));
      await openSheet(tester);
      await tester.tap(find.byTooltip('Delete saved signature'));
      await tester.pumpAndSettle();
      expect(savedTile, findsNothing);
      expect(container.read(signatureLibraryProvider).signatures, isEmpty);
    });

    testWidgets('the date stamp writes today\'s date', (tester) async {
      await pumpEditor(tester);
      await openSheet(tester);
      await tester.tap(find.text('Date stamp'));
      await tester.pumpAndSettle();
      expect((marks().single as TextAnnotation).text, stampDate(DateTime.now()));
    });

    testWidgets('the name stamp asks for the name once and remembers it', (tester) async {
      await pumpEditor(tester);
      await openSheet(tester);
      await tester.tap(find.text('Name and date'));
      await tester.pumpAndSettle();
      expect(find.text('Name for the stamp'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Varun Sharma');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect((marks().single as TextAnnotation).text, 'Varun Sharma\n${stampDate(DateTime.now())}');
      expect(container.read(signatureLibraryProvider).stampName, 'Varun Sharma');

      await openSheet(tester);
      expect(find.text('Varun Sharma'), findsOneWidget);
      await tester.tap(find.text('Name stamp'));
      await tester.pumpAndSettle();
      expect(find.text('Name for the stamp'), findsNothing);
      expect((marks().last as TextAnnotation).text, 'Varun Sharma');
    });

    testWidgets('on Basic, drawing still works but the library and stamps ask to upgrade', (tester) async {
      await pumpEditor(tester, plan: AppPlan.basic, library: SignatureLibrary(signatures: [saved('a')]));
      await openSheet(tester);
      expect(savedTile, findsNothing, reason: 'saved marks need Pro');
      expect(find.text('Pro'), findsWidgets);
      await tester.tap(find.text('Date stamp'));
      await tester.pumpAndSettle();
      expect(find.text('Upgrade to Pro'), findsWidgets);
      expect(marks(), isEmpty);
    });
  });
}
