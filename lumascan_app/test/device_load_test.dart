import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/device_load.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const roomy = DeviceLoad(availableMb: 3000, totalMb: 8000, appCpu: 0.2, thermal: 0);

  test('the text check runs when there is room', () {
    expect(affordsTextCheck(roomy, pending: 0), isTrue);
    expect(affordsTextCheck(null, pending: 0), isTrue, reason: 'unknown load: only the queue decides');
  });

  test('the text check is skipped when memory, CPU or heat run short', () {
    expect(affordsTextCheck(const DeviceLoad(availableMb: 3000, totalMb: 8000, lowMemory: true), pending: 0), isFalse);
    expect(affordsTextCheck(const DeviceLoad(availableMb: 250, totalMb: 2000), pending: 0), isFalse);
    expect(
      affordsTextCheck(const DeviceLoad(availableMb: 700, totalMb: 8000), pending: 0),
      isFalse,
      reason: 'under 12% of memory free',
    );
    expect(affordsTextCheck(const DeviceLoad(availableMb: 3000, totalMb: 8000, appCpu: 0.7), pending: 0), isFalse);
    expect(affordsTextCheck(const DeviceLoad(availableMb: 3000, totalMb: 8000, thermal: 3), pending: 0), isFalse);
  });

  test('the text check is skipped when checks pile up behind a fast batch', () {
    expect(affordsTextCheck(roomy, pending: 2), isTrue);
    expect(affordsTextCheck(roomy, pending: 3), isFalse);
    expect(affordsTextCheck(null, pending: 3), isFalse);
  });

  test('the Android probe works out the app CPU share between samples', () async {
    var call = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('lumascan/device_load'),
      (c) async => {
        'availableBytes': 2048 * 1024 * 1024,
        'totalBytes': 8192 * 1024 * 1024,
        'lowMemory': false,
        'cores': 8,
        'cpuMs': [1000, 5000][call],
        'clockMs': [10000, 12000][call++],
        'thermal': 1,
      },
    );
    final probe = PlatformDeviceLoadProbe();
    final first = (await probe.sample())!;
    expect((first.availableMb, first.totalMb, first.appCpu, first.thermal), (2048, 8192, null, 1));
    // 4 s of CPU in 2 s on 8 cores: a quarter of the phone.
    expect((await probe.sample())!.appCpu, 0.25);
  });

  test('with no platform answer the probe says nothing', () async {
    expect(await PlatformDeviceLoadProbe(const MethodChannel('lumascan/nothing_here')).sample(), isNull);
  });
}
