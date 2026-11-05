import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/features/open/open_progress.dart';

/// A screen with an Open button that runs [task] under the progress dialog
/// and records how it ended.
class OpenerHarness {
  Object? result = 'pending';
  Object? error;
  final discarded = <Object>[];
}

Future<OpenerHarness> pumpOpener(WidgetTester tester, Future<String> Function(OpenProgress) task) async {
  final h = OpenerHarness();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                try {
                  h.result = await runOpenWithProgress<String>(
                    context,
                    name: 'Big report.pdf',
                    task: task,
                    discard: h.discarded.add,
                  );
                } catch (e) {
                  h.error = e;
                }
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  return h;
}

final dialog = find.byType(OpenProgressDialog);

/// Waits past the 200 ms delay and the dialog's entrance animation.
Future<void> showDialogUp(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 300));
}

final slowText = find.textContaining('taking too long to open');

void main() {
  testWidgets('a quick open shows no dialog and returns the value', (tester) async {
    final h = await pumpOpener(tester, (_) async => 'doc');
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(dialog, findsNothing);
    expect(h.result, 'doc');
  });

  testWidgets('a slow open shows the name, step and page progress', (tester) async {
    final gate = Completer<String>();
    late OpenProgress progress;
    final h = await pumpOpener(tester, (p) {
      progress = p;
      return gate.future;
    });
    await tester.tap(find.text('Open'));
    await showDialogUp(tester);
    expect(dialog, findsOneWidget);
    expect(find.text('Big report.pdf'), findsOneWidget);

    progress.report('Reading pages', done: 120, total: 480);
    await tester.pump();
    expect(find.text('Reading pages'), findsOneWidget);
    expect(find.text('120 of 480 pages'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);

    gate.complete('doc');
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(h.result, 'doc');
  });

  Future<void> expectCancelledBy(WidgetTester tester, Future<void> Function() cancel) async {
    final gate = Completer<String>();
    late OpenProgress progress;
    final h = await pumpOpener(tester, (p) {
      progress = p;
      return gate.future;
    });
    await tester.tap(find.text('Open'));
    await showDialogUp(tester);
    await cancel();
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(h.result, isNull);
    expect(progress.cancelled, isTrue);

    // The document arrives late: it is closed, not shown.
    gate.complete('late doc');
    await tester.pump();
    expect(h.discarded, ['late doc']);
  }

  testWidgets('the X cancels opening', (tester) async {
    await expectCancelledBy(tester, () => tester.tap(find.byKey(const ValueKey('open-progress-close'))));
  });

  testWidgets('the Cancel button cancels opening', (tester) async {
    await expectCancelledBy(tester, () => tester.tap(find.byKey(const ValueKey('open-progress-cancel'))));
  });

  testWidgets('the back button cancels opening', (tester) async {
    await expectCancelledBy(tester, () async {
      final handled = await tester.binding.handlePopRoute();
      expect(handled, isTrue);
    });
  });

  testWidgets('after 10 seconds it says it is taking too long; Wait keeps going', (tester) async {
    final gate = Completer<String>();
    final h = await pumpOpener(tester, (_) => gate.future);
    await tester.tap(find.text('Open'));
    await showDialogUp(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(slowText, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(slowText, findsOneWidget);
    expect(find.text('Taking too long'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-progress-wait')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-progress-wait')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(slowText, findsNothing);
    expect(dialog, findsOneWidget);

    // Asks again 20 seconds later.
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();
    expect(slowText, findsOneWidget);

    gate.complete('doc');
    await tester.pumpAndSettle();
    expect(h.result, 'doc');
  });

  testWidgets('Cancel on the slow prompt stops opening', (tester) async {
    final gate = Completer<String>();
    final h = await pumpOpener(tester, (_) => gate.future);
    await tester.tap(find.text('Open'));
    await showDialogUp(tester);
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open-progress-cancel')));
    await tester.pumpAndSettle();
    expect(h.result, isNull);
    gate.complete('doc');
    await tester.pump();
  });

  testWidgets('time waiting for a password does not count as slow', (tester) async {
    final gate = Completer<String>();
    final password = Completer<void>();
    late OpenProgress progress;
    await pumpOpener(tester, (p) async {
      progress = p;
      await p.waitForUser(() => password.future);
      return gate.future;
    });
    await tester.tap(find.text('Open'));
    await showDialogUp(tester);
    expect(progress.waitingForUser, isTrue);
    await tester.pump();
    // Hidden so the password dialog is not drawn over it.
    expect(find.text('Opening document'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(slowText, findsNothing);
    password.complete();
    await tester.pump();
    expect(find.text('Opening document'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(slowText, findsOneWidget);
    gate.complete('doc');
    await tester.pumpAndSettle();
  });

  testWidgets('a failure closes the dialog and is passed on', (tester) async {
    final gate = Completer<String>();
    final h = await pumpOpener(tester, (_) => gate.future);
    await tester.tap(find.text('Open'));
    await showDialogUp(tester);
    gate.completeError(StateError('damaged'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(h.error, isA<StateError>());
  });

  testWidgets('a second tap while opening does nothing', (tester) async {
    final gate = Completer<String>();
    var runs = 0;
    await pumpOpener(tester, (_) {
      runs++;
      return gate.future;
    });
    await tester.tap(find.text('Open'));
    await tester.pump();
    // The barrier is up: the button can't be hit again.
    await tester.tap(find.text('Open'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));
    expect(runs, 1);
    expect(isOpeningDocument, isTrue);
    gate.complete('doc');
    await tester.pumpAndSettle();
    expect(isOpeningDocument, isFalse);
  });

  test('status text for bytes and unknown totals', () {
    expect(
      const OpenStatus('Copying', done: 3 * 1024 * 1024, total: 40 * 1024 * 1024, unit: OpenUnit.bytes).detail,
      '3.0 MB of 40 MB',
    );
    expect(const OpenStatus('Opening').fraction, isNull);
    expect(const OpenStatus('Copying', done: 5, total: 0).detail, isNull);
  });
}
