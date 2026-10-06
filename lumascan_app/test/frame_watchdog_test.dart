import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/app/frame_watchdog.dart';

void main() {
  testWidgets('redraw from the Android watchdog schedules a frame', (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);

    installFrameWatchdog();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      frameWatchdogChannel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('redraw')),
      (_) {},
    );

    expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
    frameWatchdogChannel.setMethodCallHandler(null);
  });
}
