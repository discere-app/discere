import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/model/region_option.dart';
import 'package:discere/catalog/util/region_label_resolver.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Full-page searchable, continent-grouped multi-select region picker.
///
/// Pops with the newly selected `Set<String>` of region keys on "Anwenden",
/// or with `null` if dismissed via the back button (caller should treat
/// `null` as "unchanged", and an empty set as "filter cleared").
class RegionPickerPage extends StatefulWidget {
  final List<String> availableRegionKeys;
  final Set<String> initiallySelected;

  const RegionPickerPage({
    super.key,
    required this.availableRegionKeys,
    required this.initiallySelected,
  });

  @override
  State<RegionPickerPage> createState() => _RegionPickerPageState();
}

class _RegionPickerPageState extends State<RegionPickerPage> {
  // Roughly biases toward regions with more marine biodiversity coverage
  // first; anything without a resolved continent (shouldn't normally
  // happen) is grouped last under "Other".
  static const _continentOrder = [
    Continent.asia,
    Continent.africa,
    Continent.oceania,
    Continent.europe,
    Continent.northAmerica,
    Continent.southAmerica,
    Continent.antarctica,
  ];

  final TextEditingController _searchController = TextEditingController();
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _query) return;
    setState(() => _query = query);
  }

  void _toggle(String regionKey) {
    setState(() {
      if (_selected.contains(regionKey)) {
        _selected.remove(regionKey);
      } else {
        _selected.add(regionKey);
      }
    });
  }

  /// Resolves the raw region keys to display names/continents for the
  /// current UI locale — country names are only translated for German, so
  /// this is recomputed from [widget.availableRegionKeys] rather than cached,
  /// to stay correct if the language changes while this page is open.
  List<RegionOption> _resolveRegions(BuildContext context) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    final options = widget.availableRegionKeys
        .map(
          (key) => RegionOption(
            regionKey: key,
            label: resolveCountryRegionLabel(key, german: german),
            continent: continentForCountryCode(key),
          ),
        )
        .toList();
    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  List<RegionOption> _filteredRegions(BuildContext context) {
    final regions = _resolveRegions(context);
    if (_query.isEmpty) return regions;
    return regions.where((r) => r.label.toLowerCase().contains(_query)).toList();
  }

  String _continentLabel(AppLocalizations loc, Continent? continent) {
    switch (continent) {
      case Continent.africa:
        return loc.speciesDetailContinentAfrica;
      case Continent.antarctica:
        return loc.speciesDetailContinentAntarctica;
      case Continent.asia:
        return loc.speciesDetailContinentAsia;
      case Continent.europe:
        return loc.speciesDetailContinentEurope;
      case Continent.northAmerica:
        return loc.speciesDetailContinentNorthAmerica;
      case Continent.oceania:
        return loc.speciesDetailContinentOceania;
      case Continent.southAmerica:
        return loc.speciesDetailContinentSouthAmerica;
      case null:
        return loc.regionPickerOtherContinent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = <Continent?, List<RegionOption>>{};
    for (final region in _filteredRegions(context)) {
      grouped.putIfAbsent(region.continent, () => []).add(region);
    }
    final orderedContinents = [
      ..._continentOrder.where(grouped.containsKey),
      if (grouped.containsKey(null)) null,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.regionPickerTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s16,
              vertical: AppSpacing.s8,
            ),
            child: TextField(
              key: const Key('region_picker_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.loc.regionPickerSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: orderedContinents.isEmpty
                ? Center(
                    child: Text(
                      context.loc.regionPickerNoResults,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: orderedContinents.length,
                    itemBuilder: (context, index) {
                      final continent = orderedContinents[index];
                      final regions = grouped[continent]!;
                      return _ContinentSection(
                        label: _continentLabel(context.loc, continent),
                        regions: regions,
                        selected: _selected,
                        onToggle: _toggle,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: FilledButton(
            key: const Key('region_picker_apply_button'),
            onPressed: () => Navigator.of(context).pop(_selected),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.loc.regionPickerApplyButton(_selected.length)),
          ),
        ),
      ),
    );
  }
}

class _ContinentSection extends StatelessWidget {
  final String label;
  final List<RegionOption> regions;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _ContinentSection({
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
            key: ValueKey('region_picker_option_${region.regionKey}'),
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
