import 'package:flutter/material.dart';

import '../features/pages/pages_screen.dart';

/// Colours follow the LumaScan screen design (design/styles.css).
class LumaScanApp extends StatelessWidget {
  const LumaScanApp({super.key});

  static const teal = Color(0xFF086B61);
  static const paper = Color(0xFFF5F7F4);
  static const ink = Color(0xFF172D2A);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: teal, primary: teal, surface: paper, onSurface: ink);
    return MaterialApp(
      title: 'LumaScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        appBarTheme: const AppBarTheme(backgroundColor: paper, foregroundColor: ink, elevation: 0),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
      home: const PagesScreen(),
    );
  }
}
