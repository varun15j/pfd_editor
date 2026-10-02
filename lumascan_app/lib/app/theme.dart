import 'package:flutter/material.dart';

/// LumaScan v2 design tokens (LumaScan_features.md, "Interaction and visual
/// design system"): deep ink/navy surfaces, white document canvases, cyan for
/// capture and the primary action, violet only for premium or intelligent
/// suggestions. Dark matches the v2 board (Luma_v2_design.png); light keeps
/// the same hues with darker tones so text and controls pass WCAG AA.
@immutable
class LumaColors extends ThemeExtension<LumaColors> {
  const LumaColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.premium,
    required this.onPremium,
    required this.success,
    required this.warning,
    required this.danger,
    required this.canvas,
  });

  /// Page background behind everything.
  final Color background;

  /// Cards, sheets and the bottom bar.
  final Color surface;

  /// Inputs, chips and tiles that sit on a surface.
  final Color surfaceRaised;

  /// Body text and icons.
  final Color ink;

  /// Secondary text. Still meets 4.5:1 on [surface].
  final Color muted;

  /// Dividers and outlines.
  final Color line;

  /// Primary action, selection and capture edges.
  final Color accent;
  final Color onAccent;

  /// Tinted background for selected or highlighted items.
  final Color accentSoft;

  /// Premium and intelligent features only.
  final Color premium;
  final Color onPremium;

  final Color success;
  final Color warning;
  final Color danger;

  /// Document previews stay white in both themes.
  final Color canvas;

  static const dark = LumaColors(
    background: Color(0xFF0A1322),
    surface: Color(0xFF111D31),
    surfaceRaised: Color(0xFF1A2842),
    ink: Color(0xFFEAF1F8),
    muted: Color(0xFFA3B1C6),
    line: Color(0xFF2A3A57),
    accent: Color(0xFF34D5E8),
    onAccent: Color(0xFF032029),
    accentSoft: Color(0xFF123A4A),
    premium: Color(0xFFA699FF),
    onPremium: Color(0xFF1A1240),
    success: Color(0xFF4ED492),
    warning: Color(0xFFF4B95A),
    danger: Color(0xFFFF8A80),
    canvas: Color(0xFFFFFFFF),
  );

  static const light = LumaColors(
    background: Color(0xFFF3F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEAF0F6),
    ink: Color(0xFF0E1A2B),
    muted: Color(0xFF4E5B70),
    line: Color(0xFFD5DEE8),
    accent: Color(0xFF00707F),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFD7F1F4),
    premium: Color(0xFF5B45D6),
    onPremium: Color(0xFFFFFFFF),
    success: Color(0xFF1B7A4B),
    warning: Color(0xFF8F5600),
    danger: Color(0xFFB3261E),
    canvas: Color(0xFFFFFFFF),
  );

  static LumaColors of(BuildContext context) => Theme.of(context).extension<LumaColors>()!;

  @override
  LumaColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? ink,
    Color? muted,
    Color? line,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? premium,
    Color? onPremium,
    Color? success,
    Color? warning,
    Color? danger,
    Color? canvas,
  }) => LumaColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSoft: accentSoft ?? this.accentSoft,
    premium: premium ?? this.premium,
    onPremium: onPremium ?? this.onPremium,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    canvas: canvas ?? this.canvas,
  );

  @override
  LumaColors lerp(LumaColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LumaColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      premium: l(premium, other.premium),
      onPremium: l(onPremium, other.onPremium),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      canvas: l(canvas, other.canvas),
    );
  }
}

/// 8 pt spacing grid; page margins of 16 to 24.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Horizontal page margin.
  static const page = 20.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
}

/// Smallest tap target in logical pixels (spec section 6 asks for 44; the
/// Material guideline of 48 is used).
const minTapTarget = 48.0;

ThemeData buildLumaTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? LumaColors.dark : LumaColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.ink,
    secondary: c.accent,
    onSecondary: c.onAccent,
    tertiary: c.premium,
    onTertiary: c.onPremium,
    error: c.danger,
    onError: brightness == Brightness.dark ? const Color(0xFF3B0A07) : Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceRaised,
    surfaceContainerHighest: c.surfaceRaised,
    outline: c.muted,
    outlineVariant: c.line,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md));
  const minSize = Size(minTapTarget, minTapTarget);
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);

  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    extensions: [c],
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: text.bodySmall?.copyWith(color: c.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: c.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: minSize, shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: minSize)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: minSize)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      shape: const CircleBorder(),
      elevation: 2,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(color: c.surface, elevation: 0),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceRaised,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(style: SegmentedButton.styleFrom(minimumSize: minSize)),
  );
}
