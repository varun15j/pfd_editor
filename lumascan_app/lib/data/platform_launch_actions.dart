import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';

import '../domain/launch_action.dart';

/// Quick actions on the app icon (both platforms, through the quick_actions
/// plugin) and the Android home-screen widget, whose buttons open the app
/// with an action that `MainActivity` hands over on `lumascan/launch`.
class PlatformLaunchActions implements LaunchActionSource {
  PlatformLaunchActions([this._channel = const MethodChannel('lumascan/launch')]);

  final MethodChannel _channel;
  static const _quickActions = QuickActions();

  /// Shortcuts on the app icon, in the order shown. Launchers show four at
  /// most, so this list stays at four.
  static const shortcuts = [LaunchAction.scan, LaunchAction.book, LaunchAction.idCard, LaunchAction.importPhotos];

  @override
  Future<void> start(void Function(LaunchAction action) onAction) async {
    void report(String? id) {
      final action = LaunchAction.fromId(id);
      if (action != null) onAction(action);
    }

    try {
      await _quickActions.initialize(report);
      await _quickActions.setShortcutItems([
        for (final a in shortcuts)
          ShortcutItem(type: a.id, localizedTitle: a.title, icon: Platform.isAndroid ? 'ic_shortcut_${a.id}' : null),
      ]);
    } on Object catch (e) {
      debugPrint('Quick actions unavailable: $e');
    }
    if (!Platform.isAndroid) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'action') report(call.arguments as String?);
      });
      report(await _channel.invokeMethod<String>('takePending'));
    } on Object catch (e) {
      debugPrint('Widget actions unavailable: $e');
    }
  }
}
