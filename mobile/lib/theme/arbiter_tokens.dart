// GENERATED FILE. Do not edit by hand.
// Source: tokens/tokens.json
// Run `npm run build:tokens` to regenerate.
//
// ignore_for_file: constant_identifier_names, lines_longer_than_80_chars

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spacing — 8 pt grid (4 pt half-step allowed only inside composite components)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class ArbiterSpacing {
  static const double s0 = 0.0;
  static const double s1 = 4.0;
  static const double s2 = 8.0;
  static const double s3 = 12.0;
  static const double s4 = 16.0;
  static const double s5 = 24.0;
  static const double s6 = 32.0;
  static const double s7 = 48.0;
  static const double s8 = 64.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Corner radii
// ─────────────────────────────────────────────────────────────────────────────
abstract final class ArbiterRadii {
  static const double sm = 6.0;
  static const double md = 10.0;
  static const double lg = 14.0;
  static const double xl = 22.0;
  static const double full = 9999.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Typography (numeric tokens — font families live in ArbiterFontFamily)
// ─────────────────────────────────────────────────────────────────────────────
abstract final class ArbiterFontSize {
  static const double displayLg = 40.0;
  static const double displayMd = 32.0;
  static const double headingLg = 24.0;
  static const double headingMd = 20.0;
  static const double headingSm = 16.0;
  static const double bodyLg = 16.0;
  static const double bodyMd = 14.0;
  static const double bodySm = 13.0;
  static const double labelMd = 13.0;
  static const double labelSm = 11.0;
  static const double notationLg = 18.0;
  static const double notationMd = 14.0;
  static const double notationSm = 12.0;
}
abstract final class ArbiterLineHeight {
  static const double displayLg = 48.0;
  static const double displayMd = 40.0;
  static const double headingLg = 32.0;
  static const double headingMd = 28.0;
  static const double headingSm = 24.0;
  static const double bodyLg = 24.0;
  static const double bodyMd = 20.0;
  static const double bodySm = 18.0;
  static const double labelMd = 16.0;
  static const double labelSm = 14.0;
  static const double notationLg = 24.0;
  static const double notationMd = 20.0;
  static const double notationSm = 16.0;
}
abstract final class ArbiterFontWeights {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}
abstract final class ArbiterFontFamily {
  static const String ui      = 'Inter';
  static const String mono    = 'JetBrains Mono';
  static const String display = 'Fraunces';
}

// ─────────────────────────────────────────────────────────────────────────────
// Motion
// ─────────────────────────────────────────────────────────────────────────────
abstract final class ArbiterMotionDuration {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration expressive = Duration(milliseconds: 360);
  static const Duration slow = Duration(milliseconds: 520);
}
abstract final class ArbiterMotionEasing {
  static const Cubic linear = Cubic(0.0, 0.0, 1.0, 1.0);
  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic expressive = Cubic(0.32, 0.72, 0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme-independent colors: board palettes + board highlight overlays
// ─────────────────────────────────────────────────────────────────────────────
/// User-selectable board palettes (defaults to Wood Classic). Theme-independent
/// — the colors come from [ArbiterPalette], not the active light/dark theme.
enum BoardPalette { wood, slate, mono, oled }

abstract final class ArbiterPalette {
  static const Color boardWoodSqLight = Color(0xFFF0D9B5);
  static const Color boardWoodSqDark = Color(0xFFB58863);
  static const Color boardWoodCoordinates = Color(0xFF5C4329);
  static const Color boardSlateSqLight = Color(0xFFEEEED2);
  static const Color boardSlateSqDark = Color(0xFF769656);
  static const Color boardSlateCoordinates = Color(0xFF3D4A2E);
  static const Color boardMonoSqLight = Color(0xFFE8E8E6);
  static const Color boardMonoSqDark = Color(0xFF3A3D44);
  static const Color boardMonoCoordinates = Color(0xFF94979C);
  static const Color boardOledSqLight = Color(0xFF1A1C20);
  static const Color boardOledSqDark = Color(0xFF0B0C10);
  static const Color boardOledCoordinates = Color(0xFF6B6E76);
  static const Color highlightLastMove = Color.fromRGBO(224, 169, 59, 0.32);
  static const Color highlightSelected = Color.fromRGBO(193, 154, 107, 0.40);
  static const Color highlightLegalTarget = Color.fromRGBO(63, 179, 127, 0.22);
  static const Color highlightCheck = Color.fromRGBO(217, 72, 79, 0.55);
  static const Color highlightIllegal = Color.fromRGBO(217, 72, 79, 0.45);
  static const Color highlightPremove = Color.fromRGBO(91, 141, 239, 0.30);
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme-aware color tokens — exposed via ThemeExtension<ArbiterColors>.
// Access from widgets:  Theme.of(context).extension<ArbiterColors>()!
// Or via the extension getter:  context.arbiterColors
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class ArbiterColors extends ThemeExtension<ArbiterColors> {
  const ArbiterColors({
    required this.surfaceCanvas,
    required this.surfaceRaised,
    required this.surfaceElevated,
    required this.surfaceInset,
    required this.surfaceOverlay,
    required this.contentPrimary,
    required this.contentSecondary,
    required this.contentTertiary,
    required this.contentInverse,
    required this.accentPrimary,
    required this.accentPrimaryHover,
    required this.accentPrimaryMuted,
    required this.accentSecondary,
    required this.feedbackSuccess,
    required this.feedbackInfo,
    required this.feedbackWarning,
    required this.feedbackDanger,
    required this.feedbackCritical,
    required this.confidenceLow,
    required this.confidenceMedium,
    required this.confidenceHigh,
    required this.confidenceCertain,
  });

  final Color surfaceCanvas;
  final Color surfaceRaised;
  final Color surfaceElevated;
  final Color surfaceInset;
  final Color surfaceOverlay;
  final Color contentPrimary;
  final Color contentSecondary;
  final Color contentTertiary;
  final Color contentInverse;
  final Color accentPrimary;
  final Color accentPrimaryHover;
  final Color accentPrimaryMuted;
  final Color accentSecondary;
  final Color feedbackSuccess;
  final Color feedbackInfo;
  final Color feedbackWarning;
  final Color feedbackDanger;
  final Color feedbackCritical;
  final Color confidenceLow;
  final Color confidenceMedium;
  final Color confidenceHigh;
  final Color confidenceCertain;

  static const ArbiterColors light = ArbiterColors(
    surfaceCanvas: Color(0xFFFAFAF7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceInset: Color(0xFFF1EFEA),
    surfaceOverlay: Color.fromRGBO(0, 0, 0, 0.45),
    contentPrimary: Color(0xFF101216),
    contentSecondary: Color(0xFF5A5E66),
    contentTertiary: Color(0xFF8A8E96),
    contentInverse: Color(0xFFFFFFFF),
    accentPrimary: Color(0xFFA77F50),
    accentPrimaryHover: Color(0xFFB68F60),
    accentPrimaryMuted: Color.fromRGBO(167, 127, 80, 0.12),
    accentSecondary: Color(0xFF3D5670),
    feedbackSuccess: Color(0xFF2D9963),
    feedbackInfo: Color(0xFF4A7AD4),
    feedbackWarning: Color(0xFFC28A2A),
    feedbackDanger: Color(0xFFBF3940),
    feedbackCritical: Color(0xFF7A1A1F),
    confidenceLow: Color(0xFFBF3940),
    confidenceMedium: Color(0xFFC28A2A),
    confidenceHigh: Color(0xFF4A7AD4),
    confidenceCertain: Color(0xFF2D9963),
  );

  static const ArbiterColors dark = ArbiterColors(
    surfaceCanvas: Color(0xFF0B0C10),
    surfaceRaised: Color(0xFF15171C),
    surfaceElevated: Color(0xFF1F2228),
    surfaceInset: Color(0xFF0E1014),
    surfaceOverlay: Color.fromRGBO(0, 0, 0, 0.55),
    contentPrimary: Color(0xFFF2F2F0),
    contentSecondary: Color(0xFFA8AAB1),
    contentTertiary: Color(0xFF6B6E76),
    contentInverse: Color(0xFF0B0C10),
    accentPrimary: Color(0xFFC19A6B),
    accentPrimaryHover: Color(0xFFCFAA7C),
    accentPrimaryMuted: Color.fromRGBO(193, 154, 107, 0.14),
    accentSecondary: Color(0xFF4B6584),
    feedbackSuccess: Color(0xFF3FB37F),
    feedbackInfo: Color(0xFF5B8DEF),
    feedbackWarning: Color(0xFFE0A93B),
    feedbackDanger: Color(0xFFD9484F),
    feedbackCritical: Color(0xFF8B1E24),
    confidenceLow: Color(0xFFD9484F),
    confidenceMedium: Color(0xFFE0A93B),
    confidenceHigh: Color(0xFF5B8DEF),
    confidenceCertain: Color(0xFF3FB37F),
  );

  @override
  ArbiterColors copyWith({
    Color? surfaceCanvas,
    Color? surfaceRaised,
    Color? surfaceElevated,
    Color? surfaceInset,
    Color? surfaceOverlay,
    Color? contentPrimary,
    Color? contentSecondary,
    Color? contentTertiary,
    Color? contentInverse,
    Color? accentPrimary,
    Color? accentPrimaryHover,
    Color? accentPrimaryMuted,
    Color? accentSecondary,
    Color? feedbackSuccess,
    Color? feedbackInfo,
    Color? feedbackWarning,
    Color? feedbackDanger,
    Color? feedbackCritical,
    Color? confidenceLow,
    Color? confidenceMedium,
    Color? confidenceHigh,
    Color? confidenceCertain,
  }) {
    return ArbiterColors(
      surfaceCanvas: surfaceCanvas ?? this.surfaceCanvas,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceInset: surfaceInset ?? this.surfaceInset,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      contentPrimary: contentPrimary ?? this.contentPrimary,
      contentSecondary: contentSecondary ?? this.contentSecondary,
      contentTertiary: contentTertiary ?? this.contentTertiary,
      contentInverse: contentInverse ?? this.contentInverse,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentPrimaryHover: accentPrimaryHover ?? this.accentPrimaryHover,
      accentPrimaryMuted: accentPrimaryMuted ?? this.accentPrimaryMuted,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      feedbackSuccess: feedbackSuccess ?? this.feedbackSuccess,
      feedbackInfo: feedbackInfo ?? this.feedbackInfo,
      feedbackWarning: feedbackWarning ?? this.feedbackWarning,
      feedbackDanger: feedbackDanger ?? this.feedbackDanger,
      feedbackCritical: feedbackCritical ?? this.feedbackCritical,
      confidenceLow: confidenceLow ?? this.confidenceLow,
      confidenceMedium: confidenceMedium ?? this.confidenceMedium,
      confidenceHigh: confidenceHigh ?? this.confidenceHigh,
      confidenceCertain: confidenceCertain ?? this.confidenceCertain,
    );
  }

  @override
  ArbiterColors lerp(ThemeExtension<ArbiterColors>? other, double t) {
    if (other is! ArbiterColors) return this;
    return ArbiterColors(
      surfaceCanvas: Color.lerp(surfaceCanvas, other.surfaceCanvas, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceInset: Color.lerp(surfaceInset, other.surfaceInset, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      contentPrimary: Color.lerp(contentPrimary, other.contentPrimary, t)!,
      contentSecondary: Color.lerp(contentSecondary, other.contentSecondary, t)!,
      contentTertiary: Color.lerp(contentTertiary, other.contentTertiary, t)!,
      contentInverse: Color.lerp(contentInverse, other.contentInverse, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentPrimaryHover: Color.lerp(accentPrimaryHover, other.accentPrimaryHover, t)!,
      accentPrimaryMuted: Color.lerp(accentPrimaryMuted, other.accentPrimaryMuted, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      feedbackSuccess: Color.lerp(feedbackSuccess, other.feedbackSuccess, t)!,
      feedbackInfo: Color.lerp(feedbackInfo, other.feedbackInfo, t)!,
      feedbackWarning: Color.lerp(feedbackWarning, other.feedbackWarning, t)!,
      feedbackDanger: Color.lerp(feedbackDanger, other.feedbackDanger, t)!,
      feedbackCritical: Color.lerp(feedbackCritical, other.feedbackCritical, t)!,
      confidenceLow: Color.lerp(confidenceLow, other.confidenceLow, t)!,
      confidenceMedium: Color.lerp(confidenceMedium, other.confidenceMedium, t)!,
      confidenceHigh: Color.lerp(confidenceHigh, other.confidenceHigh, t)!,
      confidenceCertain: Color.lerp(confidenceCertain, other.confidenceCertain, t)!,
    );
  }
}

extension ArbiterColorsX on BuildContext {
  ArbiterColors get arbiterColors =>
      Theme.of(this).extension<ArbiterColors>()!;
}
