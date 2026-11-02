import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/device_load.dart';
import 'package:lumascan/app/motion.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/app/providers.dart';
import 'package:lumascan/debug/phone_simulation.dart';
import 'package:lumascan/debug/phone_simulation_tile.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/imaging/render_queue.dart';

import 'support/memory_stores.dart';

class _FixedProbe implements DeviceLoadProbe {
  const _FixedProbe(this.load);
  final DeviceLoad? load;

  @override
  Future<DeviceLoad?> sample() async => load;
}

/// Varun's OnePlus: 8 GB (about 7.4 GB reported), 8 cores, half free.
const _onePlus = DeviceLoad(availableMb: 3700, totalMb: 7400, cores: 8, appCpu: 0.2);

void main() {
  group('device readings as the cheaper phone', () {
    test('2 GB entry: its memory and cores, the same free share', () {
      final load = SimulatedDeviceLoadProbe.simulate(_onePlus, SimulatedPhone.entry2gb);
      expect(load.totalMb, 1840);
      expect(load.cores, 4);
      expect(load.availableMb, 920);
      // 20% of eight fast cores is all of an entry phone's CPU.
      expect(load.appCpu, 1.0);
      expect(affordsTextCheck(load, pending: 0), isFalse);
    });

    test('4 GB mid keeps room for background work at light load', () {
      const light = DeviceLoad(availableMb: 3700, totalMb: 7400, cores: 8, appCpu: 0.05);
      final load = SimulatedDeviceLoadProbe.simulate(light, SimulatedPhone.mid4gb);
      expect(load.totalMb, 3650);
      expect(load.availableMb, 1825);
      expect(load.appCpu, closeTo(0.133, 0.01));
      expect(affordsTextCheck(load, pending: 0), isTrue);
    });

    test('little free memory reads as low memory', () {
      const tight = DeviceLoad(availableMb: 900, totalMb: 7400, cores: 8);
      final load = SimulatedDeviceLoadProbe.simulate(tight, SimulatedPhone.entry2gb);
      expect(load.availableMb, lessThan(minFreeMb));
      expect(load.lowMemory, isTrue);
    });

    test('1 GB Go: low RAM device, Low profile, no room for background reads', () {
      final load = SimulatedDeviceLoadProbe.simulate(_onePlus, SimulatedPhone.go1gb);
      expect(load.totalMb, 900);
      expect(load.lowRamDevice, isTrue);
      expect(load.availableMb, 450);
      expect(affordsTextCheck(load, pending: 0), isFalse);
      expect(
        motionProfileFor(DeviceSpec(totalMb: load.totalMb, cores: load.cores, lowRamDevice: load.lowRamDevice)),
        MotionProfile.low,
      );
      expect(SimulatedPhone.go1gb.busyCoresOn(8), 7);
    });

    test('no reading at all still gives the phone', () {
      final load = SimulatedDeviceLoadProbe.simulate(null, SimulatedPhone.mid4gb);
      expect(load.totalMb, 3650);
      expect(load.cores, 8);
    });

    test('busy cores leave about the phone\'s CPU and never every core', () {
      expect(SimulatedPhone.entry2gb.busyCoresOn(8), 6);
      expect(SimulatedPhone.mid4gb.busyCoresOn(8), 5);
      expect(SimulatedPhone.entry2gb.busyCoresOn(2), 0);
      expect(SimulatedPhone.entry2gb.busyCoresOn(1), 0);
    });
  });

  group('picked in the debug panel', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore()),
          deviceLoadProbeProvider.overrideWith((ref) {
            final phone = ref.watch(appSettingsProvider.select((s) => s.debugPhone));
            const real = _FixedProbe(_onePlus);
            return phone == null ? real : SimulatedDeviceLoadProbe(real, phone);
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the 2 GB phone makes Auto pick Low, Real goes back to High', () async {
      final c = container();
      c.listen(autoMotionProfileProvider, (_, _) {});
      await c.read(deviceSpecProvider.future);
      expect(c.read(autoMotionProfileProvider), MotionProfile.high);

      c.read(appSettingsProvider.notifier).setDebugPhone(SimulatedPhone.entry2gb);
      final spec = await c.read(deviceSpecProvider.future);
      expect(spec?.totalMb, 1840);
      expect(c.read(autoMotionProfileProvider), MotionProfile.low);

      c.read(appSettingsProvider.notifier).setDebugPhone(SimulatedPhone.mid4gb);
      await c.read(deviceSpecProvider.future);
      expect(c.read(autoMotionProfileProvider), MotionProfile.high);
    });

    test('the choices are saved', () {
      const s = AppSettings(debugPhone: SimulatedPhone.entry2gb, debugPerfOverlay: true, debugBusyCores: true);
      expect(AppSettings.fromJson(s.toJson()), s);
      expect(AppSettings.fromJson(const AppSettings().toJson()).debugPhone, isNull);
    });
  });

  test('render slots and picture cache follow the phone, and come back', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final queue = RenderQueue(concurrency: 3);
    applySimulatedPhone(SimulatedPhone.entry2gb, queue: queue);
    expect(queue.concurrency, 1);
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 32 << 20);
    applySimulatedPhone(null, queue: queue);
    expect(queue.concurrency, RenderQueue.defaultConcurrency);
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 100 << 20);
  });

  test('frame stats count frames that miss 60 Hz', () {
    final stats = FrameStats(capacity: 4);
    for (final ms in [5, 8, 20, 30, 10]) {
      stats.add(ms * 500, ms * 500, ms * 1000);
    }
    expect(stats.count, 4);
    expect(stats.slow, 2);
    expect(stats.totalMs(0.9), 30);
  });

  testWidgets('debug panel row picks a phone and turns on the overlay', (tester) async {
    final c = ProviderContainer(overrides: [appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore())]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(
            body: PhoneSimulationHost(child: SingleChildScrollView(child: PhoneSimulationTile())),
          ),
        ),
      ),
    );
    expect(find.text('This phone as it is.'), findsOneWidget);
    await tester.tap(find.text('2 GB'));
    await tester.pump();
    expect(c.read(appSettingsProvider).debugPhone, SimulatedPhone.entry2gb);
    expect(find.textContaining('Acting as 1840 MB'), findsOneWidget);

    await tester.tap(find.text('Performance overlay'));
    await tester.pump();
    expect(find.byType(PerfOverlay), findsOneWidget);
    expect(find.text('As 2 GB entry'), findsOneWidget);

    await tester.tap(find.text('Real'));
    await tester.tap(find.text('Performance overlay'));
    await tester.pump();
    expect(find.byType(PerfOverlay), findsNothing);
  });
}
