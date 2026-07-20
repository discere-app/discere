import 'package:discere/catalog/model/iucn_status.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/color_contrast_extension.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Renders a species' IUCN Red List category as a segmented status bar,
/// matching the standard IUCN/Wikipedia badge design — recreated natively
/// (no SVG asset/dependency needed) since it's fully derived from the
/// category code alone.
class IucnStatusChip extends StatelessWidget {
  final IucnStatus status;

  const IucnStatusChip({super.key, required this.status});

  static const Map<IucnStatus, Color> _spectrumColors = {
    IucnStatus.extinct: Color(0xFF000000),
    IucnStatus.extinctInTheWild: Color(0xFF3F3F3F),
    IucnStatus.criticallyEndangered: Color(0xFFD81E05),
    IucnStatus.endangered: Color(0xFFFC7F3F),
    IucnStatus.vulnerable: Color(0xFFF9E814),
    IucnStatus.nearThreatened: Color(0xFFCCE226),
    IucnStatus.leastConcern: Color(0xFF60C659),
  };
  static const Color _neutralColor = Color(0xFFB5B5B5);

  Color get _chipColor => _spectrumColors[status] ?? _neutralColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status.isOnThreatSpectrum) ...[
          Row(
            children: IucnStatus.threatSpectrum
                .map((step) {
                  final isCurrent = step == status;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: isCurrent ? 22 : 12,
                        alignment: Alignment.bottomCenter,
                        decoration: BoxDecoration(
                          color: _spectrumColors[step],
                          borderRadius: BorderRadius.circular(3),
                          border: isCurrent
                              ? Border.all(
                                  color: theme.colorScheme.onSurface,
                                  width: 1.5,
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: AppSpacing.s10),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: _chipColor,
                borderRadius: BorderRadius.circular(6),
                border: status.isOnThreatSpectrum
                    ? null
                    : Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                status.code,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _chipColor.onColor,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              _label(context.loc, status),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _label(AppLocalizations loc, IucnStatus status) {
    switch (status) {
      case IucnStatus.extinct:
        return loc.speciesIucnExtinct;
      case IucnStatus.extinctInTheWild:
        return loc.speciesIucnExtinctInTheWild;
      case IucnStatus.criticallyEndangered:
        return loc.speciesIucnCriticallyEndangered;
      case IucnStatus.endangered:
        return loc.speciesIucnEndangered;
      case IucnStatus.vulnerable:
        return loc.speciesIucnVulnerable;
      case IucnStatus.nearThreatened:
        return loc.speciesIucnNearThreatened;
      case IucnStatus.leastConcern:
        return loc.speciesIucnLeastConcern;
      case IucnStatus.dataDeficient:
        return loc.speciesIucnDataDeficient;
      case IucnStatus.notEvaluated:
        return loc.speciesIucnNotEvaluated;
    }
  }
}
