import 'package:flutter/material.dart';

/// Raw color palette for [oceanTheme] (see `ocean_theme.dart`). Values here
/// are the palette; how they're wired into [ColorScheme]/[TextTheme] roles —
/// and which UI elements each role drives — is documented there.
class OceanColors {
  // Primary & Secondary — the two brand hues. primaryBlue drives the most
  // prominent interactive accents (buttons, selected states, genus rank);
  // secondaryBlue is a darker, more reserved variant (family rank, region
  // pills) used where an accent is wanted but shouldn't compete with primary.
  static const Color primaryBlue = Color(0xFF1173d4);
  static const Color secondaryBlue = Color(0xFF00385c);

  // Third distinct accent hue, used wherever a rank/category needs a color
  // that reads as clearly different from both blues (species rank badge,
  // "endemic" badge). Picked as a violet specifically so it doesn't get
  // confused with success (green) or error (red) elsewhere in the palette.
  static const Color tertiaryAccent = Color(0xFF8b5cf6);

  // Backgrounds
  static const Color backgroundLight = Color(0xFFf6f7f8);
  static const Color backgroundDark = Color(0xFF081018);

  // Element colors
  static const Color elementDarkBackground = Color(
    0xFF1A2634,
  ); // Slate-800 approx for cards
  // One step lighter than [elementDarkBackground] — for a surface that needs
  // to read as "raised above a card", not just "raised above the page"
  // (e.g. a chip/pill sitting on top of a card's own background).
  static const Color elementDarkBackgroundElevated = Color(0xFF24313F);
  static const Color elementDarkborder = Color(0x331173d4); // primary/20

  // Section framing (subtle border for grouped content, e.g. detail/edit cards).
  // Opaque on purpose: a translucent color reads differently depending on
  // what's drawn behind it (surface vs. a lighter card fill), so this is a
  // fixed grey instead of an alpha-blended tint.
  static const Color sectionBorder = Color(0xFF2A323C);

  // Feedback
  static const Color success = Color(0xFF10b981); // Emerald
  static const Color error = Color(0xFFF44336); // standard Red

  // Text
  static const Color primaryTextLight = Color(0xFF0F172A); // Slate-900
  static const Color primaryTextDark = Color(0xFFF1F5F9); // Slate-100
  static const Color secondaryText = Color(0xFF94A3B8); // Slate-400

  // Helpers
  static const Color white = Colors.white;
  static const Color transparent = Colors.transparent;

  /// Derives a "tonal container" color the way Material 3 does — a low-alpha
  /// wash of [accent] blended onto [backgroundDark] — for badge/chip/banner
  /// backgrounds that should read as "tinted by this accent" without being
  /// as loud as the accent itself. Mirrors the tint formula
  /// `TappableSectionCard.tint`/`InfoBanner` use for the same purpose, just
  /// precomputed here so [ColorScheme] container roles can be plain values.
  static Color tonalContainer(Color accent, {double alpha = 0.16}) {
    return Color.alphaBlend(accent.withValues(alpha: alpha), backgroundDark);
  }
}
