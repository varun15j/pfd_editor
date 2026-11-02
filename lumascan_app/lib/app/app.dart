import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/debug_panel.dart';
import '../debug/phone_simulation.dart';
import '../features/capture/launch_actions_listener.dart';
import '../features/capture/shared_images_listener.dart';
import '../features/onboarding/eula_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'app_info.dart';
import 'app_lock.dart';
import 'motion.dart';
import 'preferences.dart';
import 'purchases.dart';
import 'shell.dart';
import 'theme.dart';

class LumaScanApp extends ConsumerWidget {
  const LumaScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // High or Low animations for this phone (debug panel can override).
    final motion = ref.watch(motionProfileProvider);
    return AppLockScope(
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: themeForMotion(buildLumaTheme(Brightness.light), motion),
        darkTheme: themeForMotion(buildLumaTheme(Brightness.dark), motion),
        themeMode: ref.watch(themeModeProvider),
        navigatorKey: debugNavigatorKey,
        // Debug builds: swipe in from the left edge for the debug panel. The
        // app lock covers it too.
        builder: (context, child) => MotionScope(
          profile: motion,
          child: AppLockOverlay(child: DebugPanelHost(child: PhoneSimulationHost(child: child!))),
        ),
        home: const StartGate(),
      ),
    );
  }
}

/// Picks the first screen once the saved choices are read: the End User
/// Licence Agreement until its current version is accepted, then the intro
/// until it has been seen, then the app. Waiting avoids flashing either at
/// someone who has already been through them.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts listening to the app store and restores the plan at app start.
    ref.listen(purchasesProvider, (_, _) {});
    final ready = ref.watch(appSettingsReadyProvider);
    if (!ready.hasValue) return const Scaffold(body: SizedBox.shrink());
    final eula = ref.watch(appSettingsProvider.select((s) => (s.eulaAccepted, s.eulaAcceptedVersion)));
    if (!eula.$1) return EulaScreen.gate(updated: eula.$2 > 0);
    final seen = ref.watch(appSettingsProvider.select((s) => s.onboardingSeen));
    // Images shared from the gallery wait until the intro has been seen.
    return seen
        ? const SharedImagesListener(child: LaunchActionsListener(child: AppShell()))
        : OnboardingScreen(onDone: () {});
  }
}
