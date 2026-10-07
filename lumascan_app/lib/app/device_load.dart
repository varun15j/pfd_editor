import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How busy the phone is: free memory, this app's share of the CPU and how
/// hot it runs. Background work the user did not ask for, such as reading
/// the text of each auto-captured page, runs only when there is room.
@immutable
class DeviceLoad {
  const DeviceLoad({
    required this.availableMb,
    required this.totalMb,
    this.lowMemory = false,
    this.appCpu,
    this.thermal,
  });

  /// Memory free for apps, and in all, in MB.
  final int availableMb, totalMb;

  /// Android says memory is low and it is closing background apps.
  final bool lowMemory;

  /// Share of all CPU cores this app used since the sample before, 0..1;
  /// null on the first sample.
  final double? appCpu;

  /// Android's thermal status (0 none .. 6 shutdown); null when unknown.
  final int? thermal;

  @override
  String toString() =>
      'DeviceLoad($availableMb of $totalMb MB free${lowMemory ? ', low' : ''}, '
      'cpu ${appCpu == null ? '?' : '${(appCpu! * 100).round()}%'}, thermal $thermal)';
}

/// Free memory below this, in MB or as a share of all memory, is too
/// little for text recognition (ML Kit needs about 100 MB for a photo).
const minFreeMb = 300, minFreeShare = 0.12;

/// This app using more than this share of all CPU cores leaves no room.
const maxAppCpu = 0.5;

/// Thermal status at which the phone is throttling: severe.
const hotThermal = 3;

/// Background checks waiting at most this many before new ones are skipped.
const maxPendingChecks = 2;

/// Whether there is room to read a page's text in the background, with
/// [pending] reads already waiting. With no [load] known (iOS, tests) only
/// the queue decides.
bool affordsTextCheck(DeviceLoad? load, {required int pending}) {
  if (pending > maxPendingChecks) return false;
  if (load == null) return true;
  if (load.lowMemory) return false;
  if (load.availableMb < minFreeMb || load.availableMb < load.totalMb * minFreeShare) return false;
  if ((load.appCpu ?? 0) > maxAppCpu) return false;
  return (load.thermal ?? 0) < hotThermal;
}

/// Reads the [DeviceLoad] from the platform.
abstract interface class DeviceLoadProbe {
  /// The load now, or null when the platform cannot say.
  Future<DeviceLoad?> sample();
}

/// Android: asks MainActivity over a method channel. Elsewhere, and when the
/// call fails, there is no answer.
class PlatformDeviceLoadProbe implements DeviceLoadProbe {
  PlatformDeviceLoadProbe([this._channel = const MethodChannel('lumascan/device_load')]);

  final MethodChannel _channel;
  int? _cpuMs, _clockMs;

  @override
  Future<DeviceLoad?> sample() async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>('snapshot');
    } on Object catch (e) {
      debugPrint('Device load unavailable: $e');
      return null;
    }
    if (raw == null) return null;
    final cpuMs = raw['cpuMs'] as int?, clockMs = raw['clockMs'] as int?;
    final cores = raw['cores'] as int? ?? 1;
    double? appCpu;
    if (cpuMs != null && clockMs != null && _cpuMs != null && _clockMs != null && clockMs > _clockMs!) {
      appCpu = (cpuMs - _cpuMs!) / ((clockMs - _clockMs!) * cores);
    }
    _cpuMs = cpuMs;
    _clockMs = clockMs;
    const mb = 1024 * 1024;
    return DeviceLoad(
      availableMb: ((raw['availableBytes'] as int?) ?? 0) ~/ mb,
      totalMb: ((raw['totalBytes'] as int?) ?? 0) ~/ mb,
      lowMemory: raw['lowMemory'] as bool? ?? false,
      appCpu: appCpu,
      thermal: raw['thermal'] as int?,
    );
  }
}
