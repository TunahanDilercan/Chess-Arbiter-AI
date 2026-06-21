// Wiring of the Arbiter design tokens into MaterialApp themes.
// References the generated arbiter_tokens.dart — re-running the token build
// never touches this file. Font families ('Inter', 'JetBrains Mono',
// 'Fraunces') must match the `fonts:` declarations in pubspec.yaml.

import 'package:flutter/material.dart';
import 'arbiter_tokens.dart';

abstract final class ArbiterTheme {
  // ── Light ──────────────────────────────────────────────────────────────
  static ThemeData light() {
    const colors = ArbiterColors.light;
    return _base(colors, Brightness.light).copyWith(
      scaffoldBackgroundColor: colors.surfaceCanvas,
      colorScheme: const ColorScheme.light(
        brightness: Brightness.light,
        primary: Color(0xFFA77F50),
        onPrimary: Color(0xFFFFFFFF),
        secondary: Color(0xFF3D5670),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF101216),
        error: Color(0xFFBF3940),
      ),
    );
  }

  // ── Dark (default) ─────────────────────────────────────────────────────
  static ThemeData dark() {
    const colors = ArbiterColors.dark;
    return _base(colors, Brightness.dark).copyWith(
      scaffoldBackgroundColor: colors.surfaceCanvas,
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: Color(0xFFC19A6B),
        onPrimary: Color(0xFF0B0C10),
        secondary: Color(0xFF4B6584),
        surface: Color(0xFF15171C),
        onSurface: Color(0xFFF2F2F0),
        error: Color(0xFFD9484F),
      ),
    );
  }

  // ── Shared base ────────────────────────────────────────────────────────
  static ThemeData _base(ArbiterColors c, Brightness brightness) {
    final radiusMd = BorderRadius.circular(ArbiterRadii.md);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: ArbiterFontFamily.ui,
      extensions: <ThemeExtension<dynamic>>[c],
      textTheme: _textTheme(c),
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),

      // ── Component themes (design §9) ──────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: c.surfaceRaised,
        foregroundColor: c.contentPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: ArbiterFontFamily.display,
          fontSize: ArbiterFontSize.headingMd,
          fontWeight: ArbiterFontWeights.semibold,
          color: c.contentPrimary,
        ),
        iconTheme: IconThemeData(color: c.contentSecondary),
      ),
      iconTheme: IconThemeData(color: c.contentSecondary, size: 22),
      dividerTheme: DividerThemeData(
        color: c.surfaceElevated,
        thickness: 1,
        space: 0,
      ),
      // Primary = accent fill, content/inverse text. One per screen.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accentPrimary,
          foregroundColor: c.contentInverse,
          disabledBackgroundColor: c.surfaceElevated,
          disabledForegroundColor: c.contentTertiary,
          minimumSize: const Size.fromHeight(48),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(
              fontSize: ArbiterFontSize.bodyMd,
              fontWeight: ArbiterFontWeights.medium),
        ),
      ),
      // Secondary = 1px content/secondary border, content/primary text.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.contentPrimary,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: c.contentSecondary),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
          textStyle: const TextStyle(
              fontSize: ArbiterFontSize.bodyMd,
              fontWeight: ArbiterFontWeights.medium),
        ),
      ),
      // Tertiary / ghost = accent text only.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentPrimary,
          textStyle: const TextStyle(
              fontSize: ArbiterFontSize.bodyMd,
              fontWeight: ArbiterFontWeights.medium),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceInset,
        border: OutlineInputBorder(
            borderRadius: radiusMd, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: radiusMd, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: radiusMd,
            borderSide: BorderSide(color: c.accentPrimary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: ArbiterSpacing.s4, vertical: ArbiterSpacing.s3),
        hintStyle: TextStyle(color: c.contentTertiary),
        labelStyle: TextStyle(color: c.contentSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle: TextStyle(color: c.contentPrimary),
        actionTextColor: c.accentPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ArbiterRadii.md)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accentPrimary,
        foregroundColor: c.contentInverse,
        elevation: 2,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        modalBackgroundColor: c.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ArbiterRadii.xl)),
        ),
      ),
    );
  }

  static TextTheme _textTheme(ArbiterColors c) {
    TextStyle ui(
      double size,
      double lh,
      FontWeight w, {
      Color? color,
      String? family,
    }) =>
        TextStyle(
          fontFamily: family ?? ArbiterFontFamily.ui,
          fontSize: size,
          height: lh / size,
          fontWeight: w,
          color: color ?? c.contentPrimary,
        );

    return TextTheme(
      displayLarge: ui(ArbiterFontSize.displayLg, ArbiterLineHeight.displayLg,
          ArbiterFontWeights.semibold, family: ArbiterFontFamily.display),
      displayMedium: ui(ArbiterFontSize.displayMd, ArbiterLineHeight.displayMd,
          ArbiterFontWeights.semibold, family: ArbiterFontFamily.display),
      headlineLarge: ui(ArbiterFontSize.headingLg, ArbiterLineHeight.headingLg,
          ArbiterFontWeights.semibold),
      headlineMedium: ui(ArbiterFontSize.headingMd, ArbiterLineHeight.headingMd,
          ArbiterFontWeights.semibold),
      headlineSmall: ui(ArbiterFontSize.headingSm, ArbiterLineHeight.headingSm,
          ArbiterFontWeights.semibold),
      bodyLarge: ui(ArbiterFontSize.bodyLg, ArbiterLineHeight.bodyLg,
          ArbiterFontWeights.regular),
      bodyMedium: ui(ArbiterFontSize.bodyMd, ArbiterLineHeight.bodyMd,
          ArbiterFontWeights.regular),
      bodySmall: ui(ArbiterFontSize.bodySm, ArbiterLineHeight.bodySm,
          ArbiterFontWeights.regular, color: c.contentSecondary),
      labelMedium: ui(ArbiterFontSize.labelMd, ArbiterLineHeight.labelMd,
          ArbiterFontWeights.medium, color: c.contentSecondary),
      labelSmall: ui(ArbiterFontSize.labelSm, ArbiterLineHeight.labelSm,
          ArbiterFontWeights.semibold, color: c.contentSecondary),
    );
  }
}

// ── Notation-specific text styles (not part of MaterialApp's TextTheme) ────
//
// Chess SAN must be monospace with tabular numerals so move numbers align.
abstract final class ArbiterNotationStyles {
  static TextStyle large(BuildContext ctx) => TextStyle(
        fontFamily: ArbiterFontFamily.mono,
        fontSize: ArbiterFontSize.notationLg,
        height: ArbiterLineHeight.notationLg / ArbiterFontSize.notationLg,
        fontWeight: ArbiterFontWeights.medium,
        color: ctx.arbiterColors.contentPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle medium(BuildContext ctx) => TextStyle(
        fontFamily: ArbiterFontFamily.mono,
        fontSize: ArbiterFontSize.notationMd,
        height: ArbiterLineHeight.notationMd / ArbiterFontSize.notationMd,
        fontWeight: ArbiterFontWeights.medium,
        color: ctx.arbiterColors.contentPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle small(BuildContext ctx) => TextStyle(
        fontFamily: ArbiterFontFamily.mono,
        fontSize: ArbiterFontSize.notationSm,
        height: ArbiterLineHeight.notationSm / ArbiterFontSize.notationSm,
        fontWeight: ArbiterFontWeights.medium,
        color: ctx.arbiterColors.contentSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
