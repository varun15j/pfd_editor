import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/pdf_editor/pdf_editor_screen.dart';
import 'package:lumascan/pdf_edit/annotations.dart';
import 'package:lumascan/pdf_edit/pdf_edit_controller.dart';
import 'package:signature/signature.dart';

void main() {
  late ProviderContainer container;

  PdfEditState state() => container.read(pdfEditControllerProvider);

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(pdfEditControllerProvider.notifier)
        .open(path: '/tmp/source.pdf', name: 'Lease.pdf', pageSizes: const [(612, 792), (612, 792), (842, 595)]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PdfEditorScreen(
            pageImage: (page, {thumbnail = false}) =>
                ColoredBox(key: ValueKey('img${page.sourcePage}'), color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder pageImage(int sourcePage) => find.byKey(ValueKey('img$sourcePage'));

  testWidgets('pen draws a stroke on the current page', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Pen'));
    await tester.pump();
    final center = tester.getCenter(pageImage(1));
    final gesture = await tester.startGesture(center);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(const Offset(8, 4));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final ink = state().pages.first.annotations.single as InkAnnotation;
    expect(ink.points.length, greaterThan(5));
    expect(ink.points.first.x, closeTo(0.5, 0.02));
    expect(ink.highlighter, isFalse);
    expect(state().dirty, isTrue);
  });

  testWidgets('drawing in View mode does nothing', (tester) async {
    await pumpEditor(tester);
    await tester.drag(pageImage(1), const Offset(60, 60));
    await tester.pumpAndSettle();
    expect(state().pages.first.annotations, isEmpty);
  });

  testWidgets('text tool places a text box where the page is tapped', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Text'));
    await tester.pump();
    final rect = tester.getRect(pageImage(1));
    await tester.tapAt(rect.topLeft + Offset(rect.width * 0.25, rect.height * 0.75));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Received in full');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final text = state().pages.first.annotations.single as TextAnnotation;
    expect(text.text, 'Received in full');
    expect(text.origin.x, closeTo(0.25, 0.01));
    expect(text.origin.y, closeTo(0.75, 0.01));
    expect(find.text('Received in full'), findsOneWidget);
  });

  testWidgets('arrows move between pages and marks land on that page', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);

    await tester.tap(find.text('Highlight'));
    await tester.pump();
    await tester.dragFrom(tester.getCenter(pageImage(2)), const Offset(80, 0));
    await tester.pump();
    expect(state().pages[0].annotations, isEmpty);
    expect((state().pages[1].annotations.single as InkAnnotation).highlighter, isTrue);
  });

  testWidgets('signature is drawn on the pad and placed on the page', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Sign'));
    await tester.pumpAndSettle();
    expect(find.text('Draw your signature'), findsOneWidget);
    await tester.drag(find.byType(Signature), const Offset(120, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final sig = state().pages.first.annotations.single as SignatureAnnotation;
    expect(sig.strokes, isNotEmpty);
    expect(sig.left, closeTo((1 - sig.width) / 2, 1e-9));
    // The editor switches to Move so the signature can be dragged.
    final before = sig.left;
    final rect = tester.getRect(pageImage(1));
    final sigCenter =
        rect.topLeft +
        Offset(rect.width * (sig.left + sig.width / 2), rect.height * (sig.top + sig.heightOn(612 / 792) / 2));
    await tester.dragFrom(sigCenter, const Offset(-40, 0));
    await tester.pumpAndSettle();
    final moved = state().pages.first.annotations.single as SignatureAnnotation;
    expect(moved.left, lessThan(before));
  });

  testWidgets('organize screen reorders and deletes pages', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Organize pages'));
    await tester.pumpAndSettle();
    expect(find.text('3 pages'), findsOneWidget);

    await tester.tap(find.byTooltip('Page actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move down'));
    await tester.pumpAndSettle();
    expect(state().pages.map((p) => p.sourcePage), [2, 1, 3]);

    await tester.tap(find.byTooltip('Page actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete page'));
    await tester.pumpAndSettle();
    expect(state().pages.map((p) => p.sourcePage), [2, 1]);
    expect(find.text('Deleted page 3'), findsOneWidget);

    await tester.tap(find.text('Undo').last);
    await tester.pumpAndSettle();
    expect(state().pages.map((p) => p.sourcePage), [2, 1, 3]);

    // Tapping a page returns to the editor on that page.
    await tester.tap(find.text('Page 3'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pumpEditor(tester);
    container.read(pdfEditControllerProvider.notifier).movePage(0, 1);
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Lease.pdf'), findsOneWidget);
  });
}
