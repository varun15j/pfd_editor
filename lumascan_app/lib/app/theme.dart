import 'package:flutter/material.dart';

/// LumaScan design tokens, following the UI/UX screenshots in
/// design/UI_UX_screen: near-black screens, grey bars and sheets, white
/// labels, a blue accent and white document canvases. Dark is the default;
/// light keeps the same blue with dark text so everything passes WCAG AA.
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

  /// Dark follows the UI/UX screenshots (design/UI_UX_screen): near-black
  /// screens, grey bars and sheets, white labels and a blue accent. Every
  /// label is white or light grey on a dark surface, at least 4.5:1.
  static const dark = LumaColors(
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceRaised: Color(0xFF2C2C2C),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFFB8B8B8),
    line: Color(0xFF3D3D3D),
    accent: Color(0xFF4C9AF5),
    onAccent: Color(0xFF000000),
    accentSoft: Color(0xFF13304F),
    premium: Color(0xFF4C9AF5),
    onPremium: Color(0xFF000000),
    success: Color(0xFF1DB954),
    warning: Color(0xFFF4B95A),
    danger: Color(0xFFFF7A73),
    canvas: Color(0xFFFFFFFF),
  );

  static const light = LumaColors(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEBEBEB),
    ink: Color(0xFF111111),
    muted: Color(0xFF505050),
    line: Color(0xFFD6D6D6),
    accent: Color(0xFF0D66D0),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE3EEFC),
    premium: Color(0xFF0D66D0),
    onPremium: Color(0xFFFFFFFF),
    success: Color(0xFF1B7A4B),
    warning: Color(0xFF8F5600),
    danger: Color(0xFFB3261E),
    canvas: Color(0xFFFFFFFF),
  );

  /// Filled buttons and the camera button: the screenshots' blue with white
  /// labels (4.6:1) in both themes.
  static const action = Color(0xFF1473E6);
  static const onAction = Color(0xFFFFFFFF);

  /// The green camera button in the middle of the bottom bar (Screen 1). The
  /// white camera icon on it is 3.4:1, above the 3:1 needed for icons.
  static const scan = Color(0xFF1A9E4B);
  static const onScan = Color(0xFFFFFFFF);

  /// Falls back to the palette for the theme's brightness when a widget is
  /// built under a plain Material theme, such as a screen pumped on its own.
  static LumaColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<LumaColors>() ?? (theme.brightness == Brightness.dark ? dark : light);
  }

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

/// Compact scanner controls keep the chrome quiet without making touch
/// targets smaller. The visual icon or pill can be 20–36 dp while its hit
/// area remains [tapTarget].
abstract final class ControlMetrics {
  static const tapTarget = 48.0;
  static const visualHeight = 36.0;
  static const icon = 20.0;
  static const smallIcon = 18.0;
  static const radius = 10.0;
  static const horizontalPadding = 12.0;
}

/// Smallest tap target in logical pixels (spec section 6 asks for 44; the
/// Material guideline of 48 is used).
const minTapTarget = ControlMetrics.tapTarget;

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
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(ControlMetrics.radius));
  const minSize = Size(minTapTarget, minTapTarget);
  const compactPadding = EdgeInsets.symmetric(horizontal: ControlMetrics.horizontalPadding, vertical: Space.sm);
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink);
  final compactLabel = text.labelLarge?.copyWith(fontWeight: FontWeight.w600);

  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
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
      toolbarHeight: 56,
      actionsPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
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
      style: FilledButton.styleFrom(
        backgroundColor: LumaColors.action,
        foregroundColor: LumaColors.onAction,
        minimumSize: minSize,
        padding: compactPadding,
        shape: shape,
        textStyle: compactLabel,
        iconSize: ControlMetrics.smallIcon,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        padding: compactPadding,
        shape: shape,
        foregroundColor: c.ink,
        side: BorderSide(color: c.line),
        textStyle: compactLabel,
        iconSize: ControlMetrics.smallIcon,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minSize,
        padding: compactPadding,
        shape: shape,
        textStyle: compactLabel,
        iconSize: ControlMetrics.smallIcon,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: minSize,
        iconSize: ControlMetrics.icon,
        padding: const EdgeInsets.all((minTapTarget - ControlMetrics.icon) / 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ControlMetrics.radius)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceRaised,
      selectedColor: c.accentSoft,
      disabledColor: c.surfaceRaised.withValues(alpha: 0.45),
      labelStyle: text.labelMedium?.copyWith(color: c.ink, fontWeight: FontWeight.w600),
      secondaryLabelStyle: text.labelMedium?.copyWith(color: c.ink, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      labelPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
      side: BorderSide(color: c.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ControlMetrics.radius)),
      checkmarkColor: c.accent,
      iconTheme: IconThemeData(size: ControlMetrics.smallIcon, color: c.muted),
      brightness: brightness,
      elevation: 0,
      pressElevation: 0,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      minTileHeight: 52,
      minLeadingWidth: 28,
      horizontalTitleGap: Space.md,
      minVerticalPadding: Space.sm,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      iconColor: c.muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ControlMetrics.radius)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: LumaColors.action,
      foregroundColor: LumaColors.onAction,
      shape: CircleBorder(),
      elevation: 2,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(color: c.surface, elevation: 0),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceRaised,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: ControlMetrics.horizontalPadding, vertical: Space.md),
      prefixIconConstraints: const BoxConstraints(minWidth: minTapTarget, minHeight: minTapTarget),
      suffixIconConstraints: const BoxConstraints(minWidth: minTapTarget, minHeight: minTapTarget),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ControlMetrics.radius),
        borderSide: BorderSide.none,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: minSize,
        padding: compactPadding,
        textStyle: compactLabel,
        iconSize: ControlMetrics.smallIcon,
        shape: shape,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.line,
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      actionsPadding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
    ),
  );
}
