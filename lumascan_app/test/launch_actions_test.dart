import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/domain/launch_action.dart';
import 'package:lumascan/features/id_card/id_card_type_screen.dart';

import 'support/fake_photos.dart';
import 'support/pump_app.dart';

/// Hands the app's handler to the test, which plays the shortcut or widget.
class _FakeSource implements LaunchActionSource {
  void Function(LaunchAction)? handler;

  @override
  Future<void> start(void Function(LaunchAction action) onAction) async => handler = onAction;
}

void main() {
  test('every action has a stable id that reads back', () {
    for (final a in LaunchAction.values) {
      expect(LaunchAction.fromId(a.id), a);
    }
    expect(LaunchAction.fromId('scan'), LaunchAction.scan);
    expect(LaunchAction.fromId('import'), LaunchAction.importPhotos);
    expect(LaunchAction.fromId('nope'), isNull);
    expect(LaunchAction.fromId(null), isNull);
  });

  testWidgets('the app starts listening once it is open', (tester) async {
    final source = _FakeSource();
    await pumpApp(tester, launchActions: source);
    expect(source.handler, isNotNull);
  });

  testWidgets('Scan ID card opens the ID card studio', (tester) async {
    final source = _FakeSource();
    await pumpApp(tester, launchActions: source);
    source.handler!(LaunchAction.idCard);
    await tester.pumpAndSettle();
    expect(find.byType(IdCardTypeScreen), findsOneWidget);
  });

  testWidgets('Import photos opens the photo picker, from whatever screen is open', (tester) async {
    final source = _FakeSource();
    final picker = FakePhotoPicker();
    await pumpApp(
      tester,
      launchActions: source,
      overrides: [photoPickerProvider.overrideWithValue(picker)],
    );
    // Something else is on screen first; it is closed.
    source.handler!(LaunchAction.idCard);
    await tester.pumpAndSettle();
    source.handler!(LaunchAction.importPhotos);
    await tester.pumpAndSettle();
    expect(find.byType(IdCardTypeScreen), findsNothing);
    expect(picker.picks, 1);
    expect(picker.lastFromFiles, isFalse);
  });
}
