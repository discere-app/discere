import 'package:discere/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

/// Bordered content container used to group a labeled section of a page
/// (detail views, edit-deck settings, settings page, ...). Framed with the
/// app-wide [AppThemeExtension.sectionBorder] token rather than a hardcoded
/// color, so every section reads consistently and a new theme only has to
/// provide its own border color. [color] overrides the default surface fill
/// for sections that need a subtler/tinted background (e.g. a QR/share panel).
class SectionCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final BorderRadius borderRadius;

  const SectionCard({
    required this.child,
    this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: color ?? theme.colorScheme.surface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: theme.sectionBorderColor),
        ),
        child: child,
      ),
    );
  }
}

/// The tappable counterpart to [SectionCard]: same bordered-surface look,
/// wrapped in an [InkWell] for cards that navigate/select on tap. Pass
/// [tint] to highlight the card with a semantic color (selection, success, ...)
/// instead of the default surface/[AppThemeExtension.sectionBorder] pairing —
/// mirrors how [InfoBanner] derives its fill/border from a single color.
class TappableSectionCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? tint;

  const TappableSectionCard({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.tint,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = this.tint;

    return Material(
      color: tint?.withValues(alpha: 0.08) ?? theme.colorScheme.surface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: tint?.withValues(alpha: 0.35) ?? theme.sectionBorderColor,
              width: tint != null ? 1.25 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
