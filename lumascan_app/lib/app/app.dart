import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      home: const AppShell(),
    );
  }
}
