import 'package:discere/app/info/source_license_kind.dart';
import 'package:discere/app/info/sources_hero_palette.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Explains the licence keys the cards above only abbreviate.
class SourcesLicensesFooter extends StatelessWidget {
  final List<({String key, String? licenseUrl})> licenses;
  final AppLocalizations loc;

  const SourcesLicensesFooter({
    required this.licenses,
    required this.loc,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.only(top: AppSpacing.s48),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SourcesHeroPalette.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.sourcesAboutLicensesTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
          ),
          AppSpacing.heightS16,
          Text(
            loc.sourcesAboutLicensesDescription,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: SourcesHeroPalette.mutedText,
            ),
          ),
          AppSpacing.heightS24,
          Wrap(
            spacing: AppSpacing.s24,
            runSpacing: AppSpacing.s24,
            children: licenses
                .map((license) => _LicenseItem(licenseKey: license.key, loc: loc))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LicenseItem extends StatelessWidget {
  final String licenseKey;
  final AppLocalizations loc;

  const _LicenseItem({required this.licenseKey, required this.loc});

  String get _description => switch (sourceLicenseKindFor(licenseKey)) {
    SourceLicenseKind.ccBy => loc.sourcesLicenseCcBy,
    SourceLicenseKind.ccByNonCommercial => loc.sourcesLicenseCcByNc,
    SourceLicenseKind.allRightsReserved => loc.sourcesLicenseArr,
    SourceLicenseKind.unknown => '',
  };

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: 160,
      padding: AppSpacing.cardPaddingAll,
      decoration: BoxDecoration(
        color: SourcesHeroPalette.licenseItemBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            licenseKey,
            style: const TextStyle(
              fontSize: 10,
              color: SourcesHeroPalette.accent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          AppSpacing.heightS4,
          Text(
            _description,
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
