import 'package:discere/catalog/common/taxon_identity/common_name_hint.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class IdentityHeader extends StatelessWidget {
  final TaxonIdentityViewModel identity;

  /// Shown at the end of the badge row, for a page that lets the names in
  /// [identity] be looked at in another language. Null leaves the badge on
  /// its own.
  final Widget? languageSelector;

  const IdentityHeader({
    super.key,
    required this.identity,
    this.languageSelector,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context.loc.classificationSpecies,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              ?languageSelector,
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: CopyableText(
                  text: identity.primaryName,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                  copiedStyle: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              if (identity.isEnglishFallback)
                const CommonNameHintIcon(isEnglishFallback: true),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          CopyableText(
            text: identity.scientificName,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
            copiedStyle: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
