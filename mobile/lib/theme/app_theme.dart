import 'package:flutter/material.dart';

// ── Colour palette ─────────────────────────────────────────────────────────────

/// Arbiter AI brand colours.
///
/// Primary = FIDE-table deep green.  Accent = tournament gold.
/// Surfaces follow Material 3 elevation tonal system but remain dark.
abstract final class AppColors {
  // Brand
  static const primary      = Color(0xFF1B5E20); // deep green
  static const primaryLight = Color(0xFF2E7D32); // mid green
  static const accent       = Color(0xFFFFD700); // gold
  static const accentDim    = Color(0xFFB8960C); // muted gold

  // Surfaces
  static const background   = Color(0xFF121212);
  static const surface      = Color(0xFF1E1E1E);
  static const surfaceVar   = Color(0xFF2A2A2A);
  static const surfaceHigh  = Color(0xFF363636);

  // Content
  static const onBackground = Color(0xFFE8E8E8);
  static const onSurface    = Color(0xFFCCCCCC);
  static const onSurfaceDim = Color(0xFF888888);
  static const onSurfaceFaint = Color(0xFF505050);

  // Semantic
  static const error   = Color(0xFFCF6679);
  static const legal   = Color(0xFF4CAF50);
  static const review  = Color(0xFFFFC107);
  static const illegal = Color(0xFFE53935);

  // Chess board (Lichess classic)
  static const boardLight = Color(0xFFF0D9B5);
  static const boardDark  = Color(0xFFB58863);
}

// ── Geometry ──────────────────────────────────────────────────────────────────

abstract final class AppRadius {
  static const double card   = 8;
  static const double button = 4;
  static const double chip   = 20;
  static const double input  = 8;

  static const cardAll   = BorderRadius.all(Radius.circular(card));
  static const buttonAll = BorderRadius.all(Radius.circular(button));
  static const chipAll   = BorderRadius.all(Radius.circular(chip));
}

abstract final class AppSpacing {
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;
  static const double xxl = 48;
}

// ── Typography ─────────────────────────────────────────────────────────────────

abstract final class AppTextStyles {
  static const headline = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppColors.onBackground,
    letterSpacing: -0.5,
  );
  static const title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  static const titleSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
  );
  static const body = TextStyle(
    fontSize: 15,
    color: AppColors.onBackground,
  );
  static const bodyDim = TextStyle(
    fontSize: 15,
    color: AppColors.onSurfaceDim,
  );
  static const caption = TextStyle(
    fontSize: 12,
    color: AppColors.onSurfaceDim,
    letterSpacing: 0.3,
  );
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.onSurfaceDim,
    letterSpacing: 0.8,
  );
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onBackground,
    letterSpacing: 1,
  );
  static const monoSmall = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    color: AppColors.onSurface,
  );
}

// ── Theme ──────────────────────────────────────────────────────────────────────

final class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary:    AppColors.primary,
      secondary:  AppColors.accent,
      surface:    AppColors.surface,
      error:      AppColors.error,
      onPrimary:  Colors.white,
      onSecondary: Colors.black,
      onSurface:  AppColors.onSurface,
      onError:    Colors.white,
    ),
    scaffoldBackgroundColor: AppColors.background,

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.onBackground,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onBackground,
      ),
      iconTheme: IconThemeData(color: AppColors.onBackground),
    ),

    // TabBar
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.onSurfaceDim,
      indicatorColor: AppColors.accent,
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.buttonAll,
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppColors.accent),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.buttonAll,
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceVar,
      selectedColor: AppColors.primary,
      disabledColor: AppColors.surfaceHigh,
      labelStyle: const TextStyle(color: AppColors.onSurface, fontSize: 13),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 13),
      side: BorderSide.none,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.chipAll,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: AppColors.surfaceVar,
      thickness: 1,
      space: 0,
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.onBackground),
      actionTextColor: AppColors.accent,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
    ),

    // FAB
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.black,
      elevation: 4,
      shape: StadiumBorder(),
    ),

    // Icon
    iconTheme: const IconThemeData(
      color: AppColors.onSurfaceDim,
      size: 22,
    ),

    // Input
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVar,
      border: OutlineInputBorder(
        borderRadius: AppRadius.cardAll,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.cardAll,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.cardAll,
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      labelStyle: const TextStyle(color: AppColors.onSurfaceDim),
      hintStyle: const TextStyle(color: AppColors.onSurfaceFaint),
    ),
  );
}
