import 'package:discere/theme/app_theme_extension.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

/// Bundled locally (assets/fonts/) instead of fetched via google_fonts at
/// runtime — avoids a network dependency on first launch and the associated
/// privacy concern of sending the device's IP to Google's font CDN.
const String _lexendFontFamily = 'Lexend';

final ThemeData oceanTheme = ThemeData(
  brightness: Brightness.dark,
  primaryColor: OceanColors.primaryBlue,
  scaffoldBackgroundColor: OceanColors.backgroundDark,
  // Every role below is set explicitly rather than left to ColorScheme.dark's
  // built-in fallbacks: those fallbacks (e.g. onSurfaceVariant -> onSurface,
  // outlineVariant -> onBackground/white, surfaceContainerHighest -> surface)
  // are generic Material defaults that don't know about this palette, so
  // leaving a role unset silently produces the wrong color instead of an
  // error — e.g. "muted" text rendering at full brightness, or a supposedly
  // subtle border rendering pure white.
  colorScheme: ColorScheme.dark(
    // Genus rank, primary buttons/links, the main interactive accent.
    primary: OceanColors.primaryBlue,
    onPrimary: OceanColors.white,
    // Tonal badge/chip background for anything accented with [primary]
    // (e.g. the "scientific name" tag on create-deck, genus rank badge).
    primaryContainer: OceanColors.tonalContainer(OceanColors.primaryBlue),
    onPrimaryContainer: OceanColors.primaryTextDark,

    // Family rank, region pills — a deliberately more reserved accent than
    // primary. Dark enough itself that its tonal container needs a higher
    // blend alpha to read as a distinct panel rather than near-background.
    secondary: OceanColors.secondaryBlue,
    onSecondary: OceanColors.white,
    secondaryContainer: OceanColors.tonalContainer(
      OceanColors.secondaryBlue,
      alpha: 0.55,
    ),
    onSecondaryContainer: OceanColors.primaryTextDark,

    // Species rank, "endemic" badge — the third distinct accent hue, used
    // wherever primary/secondary would be ambiguous with genus/family.
    tertiary: OceanColors.tertiaryAccent,
    onTertiary: OceanColors.white,
    tertiaryContainer: OceanColors.tonalContainer(OceanColors.tertiaryAccent),
    onTertiaryContainer: OceanColors.primaryTextDark,

    // Delete/error affordances (swipe-to-delete background, deprecated-
    // species banner, error snackbars). Swipe-to-delete in particular needs
    // to read as clearly, unambiguously destructive — a higher blend alpha
    // than the other tonal containers, which are meant to stay calm/subtle.
    error: OceanColors.error,
    onError: OceanColors.white,
    errorContainer: OceanColors.tonalContainer(OceanColors.error, alpha: 0.4),
    onErrorContainer: OceanColors.primaryTextDark,

    // Page/card background and its default (bright) text color.
    surface: OceanColors.backgroundDark,
    onSurface: OceanColors.primaryTextDark,
    // Muted/secondary text sitting on [surface] — subtitles, descriptions,
    // metadata. This is the single most-used role in the app; it must stay
    // visibly dimmer than onSurface or "muted" text reads as regular text.
    onSurfaceVariant: OceanColors.secondaryText,

    // Elevation ladder for panels raised above the page background: "low"
    // covers cards sitting directly on the page, "high" covers a chip/pill
    // sitting on top of one of those cards. Only two visually distinct
    // tiers exist in this app's design, so the container/containerHighest
    // aliases map onto the same two colors rather than inventing more tiers.
    surfaceContainerLowest: OceanColors.backgroundDark,
    surfaceContainerLow: OceanColors.elementDarkBackground,
    surfaceContainer: OceanColors.elementDarkBackground,
    surfaceContainerHigh: OceanColors.elementDarkBackgroundElevated,
    surfaceContainerHighest: OceanColors.elementDarkBackgroundElevated,

    // General-purpose line/icon color that needs more presence than
    // [outlineVariant] (Flutter's own default input/checkbox/switch borders
    // fall back to this when not styled explicitly).
    outline: OceanColors.secondaryText,
    // Deliberately the same value as [AppThemeExtension.sectionBorder]: the
    // two are the same design concept (a subtle frame around content) and
    // should never visually drift apart.
    outlineVariant: OceanColors.sectionBorder,
  ),

  // App Bar
  appBarTheme: const AppBarTheme(
    backgroundColor: OceanColors.transparent,
    elevation: 0,
    centerTitle: false,
    iconTheme: IconThemeData(color: OceanColors.primaryTextDark),
    titleTextStyle: TextStyle(
      color: OceanColors.primaryTextDark,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5, // tight tracking
    ),
  ),

  // Bottom Navigation
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: OceanColors.transparent,
    elevation: 0,
    selectedItemColor: OceanColors.primaryBlue,
    unselectedItemColor: OceanColors.secondaryText,
    showSelectedLabels: true,
    showUnselectedLabels: true,
    type: BottomNavigationBarType.fixed,
    selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
    unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
  ),

  // Floating Action Button
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: OceanColors.primaryBlue,
    foregroundColor: OceanColors.white,
    elevation: 4,
    focusElevation: 6,
    hoverElevation: 6,
    highlightElevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
  ),

  // Elevated Button
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: OceanColors.primaryBlue,
      foregroundColor: OceanColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),

  // Card Theme
  cardTheme: CardThemeData(
    color: OceanColors.elementDarkBackground,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: OceanColors.elementDarkborder),
    ),
  ),

  // Inputs
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: OceanColors.elementDarkBackground,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OceanColors.elementDarkborder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OceanColors.elementDarkborder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: OceanColors.primaryBlue),
    ),
    labelStyle: const TextStyle(color: OceanColors.secondaryText),
    hintStyle: const TextStyle(color: OceanColors.secondaryText),
  ),

  // Typography
  textTheme: _oceanTextTheme(),

  extensions: const [
    AppThemeExtension(sectionBorder: OceanColors.sectionBorder),
  ],
);

// display/headline/title are all "heading" roles (page titles, section
// headers, card titles, deck/species names) and stay on primaryTextDark
// regardless of size — a smaller heading is still a heading, not muted
// text. body/label are "content" roles: bodyLarge/labelLarge are prominent
// content (the thing the user came to read), bodyMedium/bodySmall/labelSmall
// are secondary/supporting content (descriptions, captions, metadata) and
// use secondaryText so the hierarchy is visible without a per-call
// `.copyWith(color: colorScheme.onSurfaceVariant)` at every site.
TextTheme _oceanTextTheme() {
  final textTheme = ThemeData.dark().textTheme.copyWith(
    displayLarge: const TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: OceanColors.primaryTextDark,
    ),
    displayMedium: const TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.bold,
      color: OceanColors.primaryTextDark,
    ),
    displaySmall: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: OceanColors.primaryTextDark,
    ),
    headlineMedium: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: OceanColors.primaryTextDark,
    ),
    headlineSmall: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: OceanColors.primaryTextDark,
    ),
    titleLarge: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: OceanColors.primaryTextDark,
    ),
    titleMedium: const TextStyle(
      fontSize: 14,
      color: OceanColors.primaryTextDark,
    ),
    titleSmall: const TextStyle(
      fontSize: 12,
      color: OceanColors.primaryTextDark,
    ),
    bodyLarge: const TextStyle(
      fontSize: 14,
      color: OceanColors.primaryTextDark,
    ),
    bodyMedium: const TextStyle(fontSize: 14, color: OceanColors.secondaryText),
    bodySmall: const TextStyle(fontSize: 12, color: OceanColors.secondaryText),
    labelLarge: const TextStyle(
      fontSize: 14,
      color: OceanColors.white,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: const TextStyle(fontSize: 10, color: OceanColors.secondaryText),
  );

  return textTheme.apply(fontFamily: _lexendFontFamily);
}
