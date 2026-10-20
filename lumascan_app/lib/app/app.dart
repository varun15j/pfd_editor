import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/debug_panel.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'preferences.dart';
import 'shell.dart';
import 'theme.dart';

class LumaScanApp extends ConsumerWidget {
  const LumaScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'LumaScan',
      debugShowCheckedModeBanner: false,
      theme: buildLumaTheme(Brightness.light),
      darkTheme: buildLumaTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      navigatorKey: debugNavigatorKey,
      // Debug builds: swipe in from the left edge for the debug panel.
      builder: (context, child) => DebugPanelHost(child: child!),
      home: const StartGate(),
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
    final ready = ref.watch(appSettingsReadyProvider);
    if (!ready.hasValue) return const Scaffold(body: SizedBox.shrink());
    final seen = ref.watch(appSettingsProvider.select((s) => s.onboardingSeen));
    return seen ? const AppShell() : OnboardingScreen(onDone: () {});
  }
}
