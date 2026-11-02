import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/device_load.dart';
import 'package:lumascan/app/motion.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/app/theme.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/models.dart';
import 'package:lumascan/debug/motion_profile_tile.dart';
import 'package:lumascan/features/pages/page_image.dart';
import 'package:lumascan/features/pages/page_thumbnail.dart';

import 'support/memory_stores.dart';

class _FixedProbe implements DeviceLoadProbe {
  const _FixedProbe(this.load);
  final DeviceLoad? load;

  @override
  Future<DeviceLoad?> sample() async => load;
}

ProviderContainer _container(DeviceLoad? load) {
  final container = ProviderContainer(
    overrides: [
      appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
      deviceLoadProbeProvider.overrideWithValue(_FixedProbe(load)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('profile for the phone', () {
    test('2 GB phones, one or two cores and Android Go get Low', () {
      expect(motionProfileFor(const DeviceSpec(totalMb: 1850, cores: 8)), MotionProfile.low);
      expect(motionProfileFor(const DeviceSpec(totalMb: 950, cores: 4)), MotionProfile.low);
      expect(motionProfileFor(const DeviceSpec(totalMb: 7600, cores: 1)), MotionProfile.low);
      expect(motionProfileFor(const DeviceSpec(totalMb: 7600, cores: 2)), MotionProfile.low);
      expect(motionProfileFor(const DeviceSpec(totalMb: 3800, cores: 8, lowRamDevice: true)), MotionProfile.low);
    });

    test('3 GB and up with several cores get High', () {
      expect(motionProfileFor(const DeviceSpec(totalMb: 2800, cores: 8)), MotionProfile.high);
      expect(motionProfileFor(const DeviceSpec(totalMb: 5600, cores: 8)), MotionProfile.high);
      expect(motionProfileFor(const DeviceSpec(totalMb: 11500, cores: 8)), MotionProfile.high);
    });

    test('a phone that cannot be read gets High, as before profiles', () {
      expect(motionProfileFor(null), MotionProfile.high);
      expect(motionProfileFor(const DeviceSpec()), MotionProfile.high);
      expect(motionProfileFor(const DeviceSpec(totalMb: 0, cores: 8)), MotionProfile.high);
    });
  });

  test('Auto follows the phone and the debug choice overrides it', () async {
    final container = _container(const DeviceLoad(availableMb: 400, totalMb: 1850, cores: 4));
    expect(container.read(motionProfileProvider), MotionProfile.high, reason: 'High until the phone is read');
    await container.read(deviceSpecProvider.future);
    expect(container.read(motionProfileProvider), MotionProfile.low);

    container.read(appSettingsProvider.notifier).setDebugMotion(MotionProfile.high);
    expect(container.read(motionProfileProvider), MotionProfile.high);
    container.read(appSettingsProvider.notifier).setDebugMotion(null);
    expect(container.read(motionProfileProvider), MotionProfile.low);
  });

  test('the debug choice is saved with the settings', () {
    const settings = AppSettings(debugMotion: MotionProfile.low);
    expect(AppSettings.fromJson(settings.toJson()).debugMotion, MotionProfile.low);
    expect(AppSettings.fromJson(const AppSettings().toJson()).debugMotion, isNull);
    expect(settings.copyWith(debugMotion: null).debugMotion, isNull);
    expect(settings.copyWith(ocrLanguage: 'fr').debugMotion, MotionProfile.low);
  });

  testWidgets('Low and "remove animations" make every change instant', (tester) async {
    late Motion high, low, reduced;
    await tester.pumpWidget(
      Column(
        textDirection: TextDirection.ltr,
        children: [
          MotionScope(
            profile: MotionProfile.high,
            child: Builder(builder: (c) => _grab(c, (m) => high = m)),
          ),
          MotionScope(
            profile: MotionProfile.low,
            child: Builder(builder: (c) => _grab(c, (m) => low = m)),
          ),
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(builder: (c) => _grab(c, (m) => reduced = m)),
          ),
        ],
      ),
    );
    const d = Duration(milliseconds: 200);
    expect(high.duration(d), d);
    expect(high.pageThumbnails, isTrue);
    expect(low.duration(d), Duration.zero);
    expect(low.pageThumbnails, isFalse);
    expect(reduced.duration(d), Duration.zero);
    expect(reduced.pageThumbnails, isTrue, reason: 'only Low drops page pictures');
  });

  testWidgets('Low shows a page icon with its number instead of the picture', (tester) async {
    const page = ScanPage(id: 'p1', originalPath: '/nowhere.jpg');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLumaTheme(Brightness.light),
        home: MotionScope(
          profile: MotionProfile.low,
          child: Row(
            children: [
              SizedBox(width: 96, height: 128, child: PageThumbnail(page: page, number: 3)),
              SizedBox(width: 52, height: 68, child: PageThumbnail(page: page, number: 4)),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(PageImage), findsNothing);
    expect(find.text('Page 3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget, reason: 'small tiles show only the number');
  });

  test('Low drops route animations and the ink sparkle; High keeps the theme', () {
    final theme = buildLumaTheme(Brightness.dark);
    expect(themeForMotion(theme, MotionProfile.high), same(theme));
    final low = themeForMotion(theme, MotionProfile.low);
    expect(low.splashFactory, InkRipple.splashFactory);
    expect(low.pageTransitionsTheme.builders[TargetPlatform.android]?.transitionDuration, Duration.zero);
  });

  testWidgets('the debug panel switches the animation profile', (tester) async {
    final container = _container(const DeviceLoad(availableMb: 3000, totalMb: 7600, cores: 8));
    await container.read(deviceSpecProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MotionProfileTile())),
      ),
    );
    expect(find.text('Auto: Animation high (7600 MB, 8 cores).'), findsOneWidget);

    await tester.tap(find.text('Low'));
    await tester.pump();
    expect(container.read(motionProfileProvider), MotionProfile.low);
    expect(find.textContaining('Using Animation low'), findsOneWidget);

    await tester.tap(find.text('Auto'));
    await tester.pump();
    expect(container.read(motionProfileProvider), MotionProfile.high);
    expect(container.read(appSettingsProvider).debugMotion, isNull);
  });
}

Widget _grab(BuildContext context, void Function(Motion) out) {
  out(Motion.of(context));
  return const SizedBox.shrink();
}
