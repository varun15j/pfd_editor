import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'profile_sample.dart';
import 'profile_store.dart';

/// Debug builds only: the image-loading profiler. Off by default; switched on
/// from the debug panel (swipe in from the left edge).
final imageProfilerProvider = Provider<ImageProfiler>((ref) {
  final profiler = ImageProfiler(store: SqliteProfileStore());
  ref.onDispose(profiler.dispose);
  return profiler;
});

/// Measures how long pictures take to render and show, keeps the samples in
/// a [ProfileStore] and tells the debug overlays to redraw.
///
/// Recording is skipped entirely unless [enabled], so release builds and
/// normal use pay one boolean check per picture.
class ImageProfiler extends ChangeNotifier {
  ImageProfiler({required this.store, bool? available})
    : available = available ?? (kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST')) {
    if (this.available) unawaited(_restore());
  }

  /// True in debug builds. The panel, the labels and the Settings report
  /// exist only then.
  final bool available;

  /// Where samples are saved.
  final ProfileStore store;

  bool _enabled = false;
  bool _showLabels = true;
  bool _changed = false;

  /// The newest samples, for the panel's live figures.
  final recentSamples = <ProfileSample>[];
  static const _recentLimit = 300;

  bool get enabled => available && _enabled;

  /// Whether the red timing labels are drawn on pictures.
  bool get showLabels => enabled && _showLabels;

  set enabled(bool value) {
    if (!available || value == _enabled) return;
    _changed = true;
    _enabled = value;
    unawaited(store.writeFlag('enabled', value).catchError((_) {}));
    notifyListeners();
  }

  set showLabels(bool value) {
    if (value == _showLabels) return;
    _changed = true;
    _showLabels = value;
    unawaited(store.writeFlag('labels', value).catchError((_) {}));
    notifyListeners();
  }

  Future<void> _restore() async {
    try {
      final enabled = await store.readFlag('enabled');
      final labels = await store.readFlag('labels');
      // A switch flipped while reading wins over the saved one.
      if (_changed) return;
      _enabled = enabled ?? false;
      _showLabels = labels ?? true;
      notifyListeners();
    } on Object catch (e) {
      debugPrint('Image profiler could not read its settings: $e');
    }
  }

  void record(ProfileSample sample) {
    if (!enabled) return;
    recentSamples.add(sample);
    if (recentSamples.length > _recentLimit) recentSamples.removeAt(0);
    unawaited(store.add(sample).catchError((Object e) => debugPrint('Image profile not saved: $e')));
    notifyListeners();
  }

  Future<void> clear() async {
    recentSamples.clear();
    await store.clear();
    notifyListeners();
  }

  /// Average time per kind over [recentSamples].
  Map<ProfileKind, (int, double)> get liveAverages {
    final sums = <ProfileKind, (int, double)>{};
    for (final s in recentSamples) {
      final (n, total) = sums[s.kind] ?? (0, 0.0);
      sums[s.kind] = (n + 1, total + s.totalMs);
    }
    return {for (final e in sums.entries) e.key: (e.value.$1, e.value.$2 / e.value.$1)};
  }

  /// A readable name for the screen [context] is on: the nearest enclosing
  /// widget of this app named like a screen, such as "FilterScreen".
  static String screenOf(BuildContext context) {
    String? found;
    context.visitAncestorElements((element) {
      final name = element.widget.runtimeType.toString();
      if (!name.startsWith('_') && !_frameworkNames.contains(name) && _screenLike.hasMatch(name)) {
        found = name;
        return false;
      }
      return true;
    });
    return found ?? 'Other';
  }

  static final _screenLike = RegExp(r'(Screen|View|Gallery|Sheet|Strip)$');
  static const _frameworkNames = {
    'ListView',
    'GridView',
    'PageView',
    'ReorderableListView',
    'SingleChildScrollView',
    'CustomScrollView',
    'ScrollView',
    'NestedScrollView',
    'TabBarView',
    'BottomSheet',
    'ModalBottomSheet',
    'NavigationDrawerView',
  };
}
