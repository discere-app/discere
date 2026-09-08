import 'package:discere/catalog/model/region_option.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ContinentSection extends StatelessWidget {
  final String label;
  final List<RegionOption> regions;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const ContinentSection({
    super.key,
    required this.label,
    required this.regions,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s12,
            AppSpacing.s16,
            AppSpacing.s4,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...regions.map(
          (region) => CheckboxListTile(
            key: ValueKey('species_filter_sheet_region_${region.regionKey}'),
            value: selected.contains(region.regionKey),
            onChanged: (_) => onToggle(region.regionKey),
            title: Text(region.label),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        ),
      ],
    );
  }
}
