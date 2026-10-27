import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What came of asking the phone's owner to prove it is them.
enum DeviceAuthResult {
  success,

  /// They closed the prompt.
  cancelled,

  /// The phone has no screen lock, so there is nothing to check against.
  unavailable,

  /// Anything else, such as too many wrong tries.
  failed,
}

/// Fingerprint or face where the phone has them, with the phone's PIN,
/// pattern or passcode always offered too (DeviceAuth.kt, DeviceAuth.swift).
abstract class DeviceAuth {
  /// Whether the phone has a screen lock the app lock can lean on.
  Future<bool> isAvailable();

  /// Shows the system prompt with [reason] under the app's name.
  Future<DeviceAuthResult> authenticate(String reason);
}

class ChannelDeviceAuth implements DeviceAuth {
  const ChannelDeviceAuth();

  static const _channel = MethodChannel('lumascan/device_auth');

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<DeviceAuthResult> authenticate(String reason) async {
    try {
      final answer = await _channel.invokeMethod<String>('authenticate', {'reason': reason});
      return DeviceAuthResult.values.asNameMap()[answer] ?? DeviceAuthResult.failed;
    } on MissingPluginException {
      return DeviceAuthResult.unavailable;
    } on PlatformException {
      return DeviceAuthResult.failed;
    }
  }
}

final deviceAuthProvider = Provider<DeviceAuth>((ref) => const ChannelDeviceAuth());
