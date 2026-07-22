import 'package:discere/catalog/common/region_abundance_label.dart';
import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/shared/extensions/color_contrast_extension.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Color-coded pill showing how commonly a species is sighted, from
/// [RegionAbundance.abundant] (green) down to [RegionAbundance.scarce]
/// (orange) — or a neutral outline for `null` ("present but unrated").
/// Shared between the taxon species picker and the species detail page so
/// both read the same frequency signal consistently.
class RegionAbundanceChip extends StatelessWidget {
  final RegionAbundance? abundance;

  const RegionAbundanceChip({super.key, required this.abundance});

  static const Map<RegionAbundance, Color> _colors = {
    RegionAbundance.abundant: Color(0xFF2E7D32),
    RegionAbundance.common: Color(0xFF60C659),
    RegionAbundance.fairlyCommon: Color(0xFFCCE226),
    RegionAbundance.occasional: Color(0xFFF9E814),
    RegionAbundance.scarce: Color(0xFFFC7F3F),
  };
  static const Color _neutralColor = Color(0xFFB5B5B5);

  Color get _chipColor => _colors[abundance] ?? _neutralColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _chipColor;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: abundance == null
            ? Border.all(color: theme.colorScheme.outlineVariant)
            : null,
      ),
      child: Text(
        regionAbundanceLabel(context.loc, abundance),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: color.onColor,
        ),
      ),
    );
  }
}
