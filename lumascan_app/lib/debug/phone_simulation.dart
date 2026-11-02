import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/preferences.dart';
import '../app/providers.dart';
import '../domain/simulated_phone.dart';
import '../imaging/render_queue.dart';

export '../domain/simulated_phone.dart';

/// Flutter's own picture cache size, restored when the simulation stops.
const _defaultImageCacheBytes = 100 << 20;

/// The phone the app acts as in debug builds; null for this phone as it is.
final simulatedPhoneProvider = Provider<SimulatedPhone?>(
  (ref) => kDebugMode ? ref.watch(appSettingsProvider.select((s) => s.debugPhone)) : null,
);

/// Debug builds only: applies the "Simulate phone" choice from the debug
/// panel (picture cache size, renders at once, busy cores) and draws the
/// performance overlay when it is on. Release builds get [child] untouched.
class PhoneSimulationHost extends ConsumerStatefulWidget {
  const PhoneSimulationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PhoneSimulationHost> createState() => _PhoneSimulationHostState();
}

class _PhoneSimulationHostState extends ConsumerState<PhoneSimulationHost> {
  final _busy = BusyCores();

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    ref.listenManual(simulatedPhoneProvider, (_, phone) => _apply(phone), fireImmediately: true);
    ref.listenManual(
      appSettingsProvider.select((s) => s.debugBusyCores),
      (_, _) => _apply(ref.read(simulatedPhoneProvider)),
    );
  }

  void _apply(SimulatedPhone? phone) {
    applySimulatedPhone(phone, queue: ref.read(renderQueueProvider));
    final busy = phone != null && ref.read(appSettingsProvider).debugBusyCores;
    _busy.keepBusy(busy ? phone.busyCoresOn(Platform.numberOfProcessors) : 0);
  }

  @override
  void dispose() {
    _busy.keepBusy(0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;
    final overlay = ref.watch(appSettingsProvider.select((s) => s.debugPerfOverlay));
    return Stack(
      children: [
        widget.child,
        if (overlay) PerfOverlay(phone: ref.watch(simulatedPhoneProvider)),
      ],
    );
  }
}

SimulatedPhone? _lastApplied;

/// Sets the picture cache and render slots for [phone], or back to this
/// phone's own when null.
void applySimulatedPhone(SimulatedPhone? phone, {required RenderQueue queue}) {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = phone == null ? _defaultImageCacheBytes : phone.imageCacheMb << 20;
  queue.concurrency = phone?.renderSlots ?? RenderQueue.defaultConcurrency;
  if (phone == _lastApplied) return;
  _lastApplied = phone;
  debugPrint(
    'Simulate phone: ${phone?.label ?? 'off'}, image cache ${cache.maximumSizeBytes >> 20} MB, '
    '${queue.concurrency} renders at once',
  );
}

/// Keeps some cores busy with plain arithmetic in background isolates, so the
/// app competes for the CPU as it would on a phone with fewer, slower cores.
/// The phone gets warm while this runs.
class BusyCores {
  final _isolates = <Isolate>[];
  int _wanted = 0;

  int get running => _isolates.length;

  Future<void> keepBusy(int count) async {
    _wanted = count;
    while (_isolates.length > _wanted) {
      _isolates.removeLast().kill(priority: Isolate.immediate);
    }
    while (_isolates.length < _wanted) {
      final isolate = await Isolate.spawn(_spin, null, debugName: 'busy core');
      // Asked for fewer while starting.
      if (_isolates.length >= _wanted) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _isolates.add(isolate);
    }
  }

  static void _spin(void _) {
    var x = 0;
    while (true) {
      for (var i = 0; i < 1 << 20; i++) {
        x = (x * 31 + i) & 0xffffff;
      }
      if (x == -1) return; // Never true; keeps the loop from being removed.
    }
  }
}

/// Frame times of the last [capacity] frames, for the overlay.
class FrameStats {
  FrameStats({this.capacity = 120});

  final int capacity;
  final _build = ListQueue<int>(), _raster = ListQueue<int>(), _total = ListQueue<int>();

  /// A frame slower than this misses a 60 Hz refresh, which entry phones have.
  static const slowMicros = 16667;

  void add(int buildMicros, int rasterMicros, int totalMicros) {
    for (final (q, v) in [(_build, buildMicros), (_raster, rasterMicros), (_total, totalMicros)]) {
      q.addLast(v);
      if (q.length > capacity) q.removeFirst();
    }
  }

  void addTiming(FrameTiming t) =>
      add(t.buildDuration.inMicroseconds, t.rasterDuration.inMicroseconds, t.totalSpan.inMicroseconds);

  int get count => _total.length;
  int get slow => _total.where((v) => v > slowMicros).length;

  double buildMs([double pct = 0.5]) => _pct(_build, pct);
  double rasterMs([double pct = 0.5]) => _pct(_raster, pct);
  double totalMs([double pct = 0.5]) => _pct(_total, pct);

  static double _pct(Iterable<int> values, double pct) {
    if (values.isEmpty) return 0;
    final sorted = values.toList()..sort();
    return sorted[((sorted.length - 1) * pct).round()] / 1000;
  }
}

/// Debug builds: frame times, slow frames and the app's memory, drawn over
/// the top of the screen. Touches pass through it.
class PerfOverlay extends StatefulWidget {
  const PerfOverlay({super.key, this.phone});

  /// The phone being acted as, whose memory budget the app is held to.
  final SimulatedPhone? phone;

  @override
  State<PerfOverlay> createState() => _PerfOverlayState();
}

class _PerfOverlayState extends State<PerfOverlay> {
  final _frames = FrameStats();
  Timer? _tick;
  int _rssMb = 0, _peakMb = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _sample();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(_sample));
  }

  void _onTimings(List<FrameTiming> timings) => timings.forEach(_frames.addTiming);

  void _sample() {
    try {
      _rssMb = ProcessInfo.currentRss >> 20;
    } on Object {
      _rssMb = 0;
    }
    if (_rssMb > _peakMb) _peakMb = _rssMb;
  }

  @override
  void dispose() {
    _tick?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final cache = PaintingBinding.instance.imageCache;
    final over = phone != null && _rssMb > phone.memoryBudgetMb;
    final slow = _frames.slow;
    const style = TextStyle(
      color: Colors.white,
      fontSize: 11,
      height: 1.3,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    String ms(double v) => v.toStringAsFixed(1);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 4,
      right: 4,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: DefaultTextStyle(
              style: style,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    phone == null ? 'This phone' : 'As ${phone.label}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('UI ${ms(_frames.buildMs())} / p90 ${ms(_frames.buildMs(0.9))} ms'),
                  Text('GPU ${ms(_frames.rasterMs())} / p90 ${ms(_frames.rasterMs(0.9))} ms'),
                  Text(
                    'Slow $slow of ${_frames.count}',
                    style: TextStyle(color: slow > _frames.count / 10 ? Colors.orangeAccent : Colors.white),
                  ),
                  Text(
                    'RAM $_rssMb${phone == null ? '' : ' / ${phone.memoryBudgetMb}'} MB, peak $_peakMb',
                    style: TextStyle(color: over ? Colors.redAccent : Colors.white),
                  ),
                  Text('Pictures ${cache.currentSizeBytes >> 20} / ${cache.maximumSizeBytes >> 20} MB'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
