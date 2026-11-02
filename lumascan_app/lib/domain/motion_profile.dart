import 'package:flutter/foundation.dart';

/// How much the app animates and how many page pictures it draws, picked for
/// the phone it runs on (docs/animation-profiles.md).
enum MotionProfile {
  /// Phones with room to spare (about 6 GB and many cores): every animation,
  /// live page thumbnails, the fanned stack of the last shots in the camera.
  high('Animation high'),

  /// Entry phones (2 GB or less, one or two cores, Android Go): no decorative
  /// animation, and page pictures only where a page is opened. Grids and
  /// strips show a page icon with its number instead.
  low('Animation low');

  const MotionProfile(this.label);
  final String label;
}

/// What the phone has, read once at start.
@immutable
class DeviceSpec {
  const DeviceSpec({this.totalMb, this.cores, this.lowRamDevice = false});

  /// All memory in MB as Android reports it (a little under the box figure:
  /// a 2 GB phone says about 1.8 GB). Null when unknown.
  final int? totalMb;

  /// CPU cores the app may use. Null when unknown.
  final int? cores;

  /// Android says this is a low memory device (Android Go).
  final bool lowRamDevice;

  @override
  String toString() => 'DeviceSpec(${totalMb ?? '?'} MB, ${cores ?? '?'} cores${lowRamDevice ? ', low RAM' : ''})';
}

/// Memory at or below this, in MB as reported, makes a phone Low. Catches
/// 2 GB phones (about 1.8 GB reported) and leaves 3 GB phones on High.
const lowProfileMaxMb = 2560;

/// This many cores or fewer makes a phone Low, whatever its memory.
const lowProfileMaxCores = 2;

/// The profile for [spec]. Unknown phones (iOS, tests, a failed call) get
/// High, which is how the app behaved before profiles existed.
MotionProfile motionProfileFor(DeviceSpec? spec) {
  if (spec == null) return MotionProfile.high;
  if (spec.lowRamDevice) return MotionProfile.low;
  if (spec.cores case final cores? when cores <= lowProfileMaxCores) return MotionProfile.low;
  if (spec.totalMb case final mb? when mb > 0 && mb <= lowProfileMaxMb) return MotionProfile.low;
  return MotionProfile.high;
}
