import 'package:flutter/material.dart';

/// Theme-swappable design tokens that don't fit [ColorScheme]'s roles.
/// Add fields here (and set them per-theme) instead of hardcoding a color
/// value in a widget — a new theme only has to provide its own values.
@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  /// Subtle border used to frame a content section (see `SectionCard`).
  /// A theme is expected to set this to the same value as its
  /// `ColorScheme.outlineVariant` — this field exists so [SectionCard] and
  /// friends can style themselves before a theme has opted into providing
  /// this extension at all, not to diverge from `outlineVariant` on themes
  /// that do.
  final Color sectionBorder;

  const AppThemeExtension({required this.sectionBorder});

  @override
  AppThemeExtension copyWith({Color? sectionBorder}) {
    return AppThemeExtension(
      sectionBorder: sectionBorder ?? this.sectionBorder,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      sectionBorder: Color.lerp(sectionBorder, other.sectionBorder, t)!,
    );
  }
}

extension AppThemeExtensionTheme on ThemeData {
  /// Falls back to [ColorScheme.outlineVariant] if a theme doesn't register
  /// [AppThemeExtension], so widgets stay safe under a theme that hasn't
  /// opted in yet. Prefer this over [AppThemeExtensionContext.sectionBorderColor]
  /// when the widget already has a `theme` local, to avoid a second
  /// `Theme.of` lookup.
  Color get sectionBorderColor =>
      extension<AppThemeExtension>()?.sectionBorder ??
      colorScheme.outlineVariant;
}

extension AppThemeExtensionContext on BuildContext {
  Color get sectionBorderColor => Theme.of(this).sectionBorderColor;
}
