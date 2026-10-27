import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/debug_panel.dart';
import '../features/capture/shared_images_listener.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'app_info.dart';
import 'app_lock.dart';
import 'preferences.dart';
import 'purchases.dart';
import 'shell.dart';
import 'theme.dart';

class LumaScanApp extends ConsumerWidget {
  const LumaScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppLockScope(
      child: MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: buildLumaTheme(Brightness.light),
        darkTheme: buildLumaTheme(Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        navigatorKey: debugNavigatorKey,
        // Debug builds: swipe in from the left edge for the debug panel. The
        // app lock covers it too.
        builder: (context, child) => AppLockOverlay(child: DebugPanelHost(child: child!)),
        home: const StartGate(),
      ),
    );
  }
}

/// Picks the first screen once the saved choices are read: the intro until it
/// has been seen, then the app. Waiting avoids flashing the intro at someone
/// who has already seen it.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts listening to the app store and restores the plan at app start.
    ref.listen(purchasesProvider, (_, _) {});
    final ready = ref.watch(appSettingsReadyProvider);
    if (!ready.hasValue) return const Scaffold(body: SizedBox.shrink());
    final seen = ref.watch(appSettingsProvider.select((s) => s.onboardingSeen));
    // Images shared from the gallery wait until the intro has been seen.
    return seen ? const SharedImagesListener(child: AppShell()) : OnboardingScreen(onDone: () {});
  }
}
