import 'package:discere/catalog/common/continent_label.dart';
import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/model/region_option.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/continent_section.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Picks regions, grouped by continent, with a search field over their names.
///
/// Takes the already-filtered [regions] rather than the search text: which
/// regions exist and how the query narrows them is the sheet's business, and
/// resolving them needs its widget configuration.
class RegionFilterTab extends StatelessWidget {
  /// Every region the taxon actually occurs in. Empty means the taxon has no
  /// region data at all, which reads differently from a search that matched
  /// nothing.
  final bool hasAnyRegion;

  /// The regions matching the current search, in display order.
  final List<RegionOption> regions;

  /// Continents in the order they should appear. Regions the catalog could
  /// not place are appended under their own heading.
  final List<Continent> continentOrder;

  final Set<String> selectedRegionKeys;
  final TextEditingController searchController;
  final void Function(String regionKey) onToggle;

  const RegionFilterTab({
    super.key,
    required this.hasAnyRegion,
    required this.regions,
    required this.continentOrder,
    required this.selectedRegionKeys,
    required this.searchController,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasAnyRegion) return _EmptyNotice(padded: true);

    final grouped = <Continent?, List<RegionOption>>{};
    for (final region in regions) {
      grouped.putIfAbsent(region.continent, () => []).add(region);
    }
    final orderedContinents = [
      ...continentOrder.where(grouped.containsKey),
      if (grouped.containsKey(null)) null,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8,
          ),
          child: TextField(
            key: const Key('species_filter_sheet_region_search'),
            controller: searchController,
            decoration: InputDecoration(
              hintText: context.loc.regionPickerSearchHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: searchController.clear,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: orderedContinents.isEmpty
              ? const _EmptyNotice()
              : ListView(
                  children: orderedContinents
                      .map(
                        (continent) => ContinentSection(
                          label: continentLabel(context.loc, continent),
                          regions: grouped[continent]!,
                          selected: selectedRegionKeys,
                          onToggle: onToggle,
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  final bool padded;

  const _EmptyNotice({this.padded = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      context.loc.regionPickerNoResults,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Center(
      child: padded
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.s24),
              child: text,
            )
          : text,
    );
  }
}
