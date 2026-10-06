import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Channel the Android first-frame watchdog uses (see MainActivity.kt, UX-10).
const frameWatchdogChannel = MethodChannel('lumascan/frame_watchdog');

/// Answers the watchdog's `redraw` request with a forced frame.
///
/// After the window's surface is recreated, the engine can wait for a frame
/// while Dart has nothing dirty to draw. One forced frame unblocks it.
void installFrameWatchdog() {
  frameWatchdogChannel.setMethodCallHandler((call) async {
    if (call.method == 'redraw') SchedulerBinding.instance.scheduleForcedFrame();
    return null;
  });
}
