import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/ui/compact_action_button.dart';
import 'package:lumascan/ui/luma_icons.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: buildLumaTheme(Brightness.light),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('compact toolbar action keeps a 48 dp accessible target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      app(
        CompactActionButton(
          icon: LumaIcons.crop,
          label: 'Crop',
          selected: true,
          onPressed: () => taps++,
        ),
      ),
    );

    final size = tester.getSize(find.byType(CompactActionButton));
    expect(size.width, greaterThanOrEqualTo(minTapTarget));
    expect(size.height, greaterThanOrEqualTo(minTapTarget));
    expect(
      tester.widget<Icon>(find.byIcon(LumaIcons.crop)).size,
      ControlMetrics.toolbarIcon,
    );

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

    await tester.tap(find.bySemanticsLabel('Crop'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('global buttons stay compact without shrinking their hit areas', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(LumaIcons.share),
              label: const Text('Export'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(LumaIcons.add),
              label: const Text('Add'),
            ),
            IconButton(
              tooltip: 'Search',
              onPressed: () {},
              icon: const Icon(LumaIcons.search),
            ),
          ],
        ),
      ),
    );

    for (final finder in [
      find.byType(FilledButton),
      find.byType(OutlinedButton),
      find.byType(IconButton),
    ]) {
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(minTapTarget));
      expect(size.height, greaterThanOrEqualTo(minTapTarget));
    }
  });

  testWidgets('compact action remains laid out at 200 percent text size', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: CompactActionButton(
            icon: LumaIcons.scan,
            label: 'Scan document',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(CompactActionButton)).height,
      greaterThanOrEqualTo(minTapTarget),
    );
  });
}
