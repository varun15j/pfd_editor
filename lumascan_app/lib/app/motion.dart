import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/motion_profile.dart';
import 'preferences.dart';
import 'providers.dart';

export '../domain/motion_profile.dart';

/// What the phone has, read once from the platform. Null when it cannot say
/// (iOS, tests), which means High.
final deviceSpecProvider = FutureProvider<DeviceSpec?>((ref) async {
  final load = await ref.watch(deviceLoadProbeProvider).sample();
  if (load == null) return null;
  final spec = DeviceSpec(totalMb: load.totalMb, cores: load.cores, lowRamDevice: load.lowRamDevice);
  debugPrint('Animation profile: ${motionProfileFor(spec).name} for $spec');
  return spec;
});

/// The profile picked for this phone (Auto). High until the phone is read.
final autoMotionProfileProvider = Provider<MotionProfile>(
  (ref) => motionProfileFor(ref.watch(deviceSpecProvider).value),
);

/// The profile the app uses: the phone's own, or in debug builds the one
/// picked in the debug panel.
final motionProfileProvider = Provider<MotionProfile>((ref) {
  final picked = kDebugMode ? ref.watch(appSettingsProvider.select((s) => s.debugMotion)) : null;
  return picked ?? ref.watch(autoMotionProfileProvider);
});

/// Puts the [MotionProfile] where every widget can read it with
/// [Motion.of], including plain StatelessWidgets.
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.profile, required super.child});

  final MotionProfile profile;

  @override
  bool updateShouldNotify(MotionScope old) => old.profile != profile;
}

/// How a widget should move and what it should draw, from the
/// [MotionProfile] and the system's "remove animations" setting.
@immutable
class Motion {
  const Motion(this.profile, {this.reduced = false});

  /// The app's profile. Outside a [MotionScope] (most widget tests) High.
  final MotionProfile profile;

  /// The system asks for animations to be turned off (accessibility).
  final bool reduced;

  static Motion of(BuildContext context) => Motion(
    context.dependOnInheritedWidgetOfExactType<MotionScope>()?.profile ?? MotionProfile.high,
    reduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
  );

  bool get isLow => profile == MotionProfile.low;

  /// Decorative animations play: fades, pops, slides, the capture flash.
  bool get animates => !isLow && !reduced;

  /// Grids, lists and strips draw each page's picture. On Low they show a
  /// page icon with its number, and the picture only once a page is opened.
  bool get pageThumbnails => !isLow;

  /// [full] where animations play, otherwise none, so the change is instant.
  Duration duration(Duration full) => animates ? full : Duration.zero;

  /// Scrolls [controller] to [offset]: animated where animations play,
  /// otherwise a jump (an animation of zero length is not allowed).
  void scrollTo(ScrollController controller, double offset, {Duration duration = const Duration(milliseconds: 250)}) {
    if (animates) {
      controller.animateTo(offset, duration: duration, curve: Curves.easeOut);
    } else {
      controller.jumpTo(offset);
    }
  }

  /// Like [scrollTo] for a [PageController].
  void toPage(PageController controller, int page, {Duration duration = const Duration(milliseconds: 250)}) {
    if (animates) {
      controller.animateToPage(page, duration: duration, curve: Curves.easeOut);
    } else {
      controller.jumpToPage(page);
    }
  }
}

/// [theme] tuned for [profile]. Low drops route transitions (each one
/// snapshots two screens) and the shader-based ink sparkle for a plain
/// ripple. iOS keeps its own transition for the back swipe. High keeps the
/// platform defaults.
ThemeData themeForMotion(ThemeData theme, MotionProfile profile) {
  if (profile == MotionProfile.high) return theme;
  const instant = _InstantPageTransitionsBuilder();
  return theme.copyWith(
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: instant,
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: instant,
        TargetPlatform.linux: instant,
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: instant,
      },
    ),
  );
}

/// Shows the new screen straight away, with no animation.
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
