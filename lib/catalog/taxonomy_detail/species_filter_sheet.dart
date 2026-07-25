import 'package:discere/catalog/common/region_abundance_label.dart';
import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/region_option.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_species_selection_presenter.dart';
import 'package:discere/catalog/util/region_label_resolver.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The combined outcome of [showSpeciesFilterSheet]: the chosen region keys
/// (empty means "no region filter") and abundance tiers (all tiers means "no
/// frequency filter").
class SpeciesFilterResult {
  final Set<String> regionKeys;
  final Set<RegionAbundance?> tiers;

  const SpeciesFilterResult({required this.regionKeys, required this.tiers});
}

/// Opens a single bottom sheet showing every filter dimension for the taxon
/// species-selection screen (region, frequency) directly, with one shared
/// "Anwenden" button — no drill-down into separate screens.
Future<SpeciesFilterResult?> showSpeciesFilterSheet(
  BuildContext context, {
  required List<String> availableRegionKeys,
  required Set<String> initiallySelectedRegionKeys,
  required Set<RegionAbundance?> initiallySelectedTiers,
}) {
  return showModalBottomSheet<SpeciesFilterResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SpeciesFilterSheet(
      availableRegionKeys: availableRegionKeys,
      initiallySelectedRegionKeys: initiallySelectedRegionKeys,
      initiallySelectedTiers: initiallySelectedTiers,
    ),
  );
}

class SpeciesFilterSheet extends StatefulWidget {
  final List<String> availableRegionKeys;
  final Set<String> initiallySelectedRegionKeys;
  final Set<RegionAbundance?> initiallySelectedTiers;

  const SpeciesFilterSheet({
    super.key,
    required this.availableRegionKeys,
    required this.initiallySelectedRegionKeys,
    required this.initiallySelectedTiers,
  });

  @override
  State<SpeciesFilterSheet> createState() => _SpeciesFilterSheetState();
}

class _SpeciesFilterSheetState extends State<SpeciesFilterSheet>
    with SingleTickerProviderStateMixin {
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

  late final TabController _tabController;
  final TextEditingController _regionSearchController =
      TextEditingController();
  late Set<String> _selectedRegionKeys;
  late Set<RegionAbundance?> _selectedTiers;
  String _regionQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedRegionKeys = {...widget.initiallySelectedRegionKeys};
    _selectedTiers = {...widget.initiallySelectedTiers};
    _regionSearchController.addListener(_onRegionQueryChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _regionSearchController.removeListener(_onRegionQueryChanged);
    _regionSearchController.dispose();
    super.dispose();
  }

  void _onRegionQueryChanged() {
    final query = _regionSearchController.text.trim().toLowerCase();
    if (query == _regionQuery) return;
    setState(() => _regionQuery = query);
  }

  void _toggleRegion(String regionKey) {
    setState(() {
      if (_selectedRegionKeys.contains(regionKey)) {
        _selectedRegionKeys.remove(regionKey);
      } else {
        _selectedRegionKeys.add(regionKey);
      }
    });
  }

  void _toggleTier(RegionAbundance? tier) {
    setState(() {
      if (_selectedTiers.contains(tier)) {
        _selectedTiers.remove(tier);
      } else {
        _selectedTiers.add(tier);
      }
    });
  }

  /// Resolves the raw region keys to display names/continents for the
  /// current UI locale — country names are only translated for German, so
  /// this is recomputed rather than cached, to stay correct if the language
  /// changes while this sheet is open.
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
    if (_regionQuery.isEmpty) return regions;
    return regions.where((r) => r.label.toLowerCase().contains(_regionQuery)).toList();
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

  void _apply() {
    Navigator.of(context).pop(
      SpeciesFilterResult(regionKeys: _selectedRegionKeys, tiers: _selectedTiers),
    );
  }

  bool get _hasActiveFilters =>
      _selectedRegionKeys.isNotEmpty ||
      _selectedTiers.length <
          TaxonomySpeciesSelectionPresenter.allFrequencyTiers.length;

  void _resetFilters() {
    setState(() {
      _selectedRegionKeys = {};
      _selectedTiers = {...TaxonomySpeciesSelectionPresenter.allFrequencyTiers};
    });
  }

  Widget _buildRegionTab(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = <Continent?, List<RegionOption>>{};
    for (final region in _filteredRegions(context)) {
      grouped.putIfAbsent(region.continent, () => []).add(region);
    }
    final orderedContinents = [
      ..._continentOrder.where(grouped.containsKey),
      if (grouped.containsKey(null)) null,
    ];

    if (widget.availableRegionKeys.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Text(
            context.loc.regionPickerNoResults,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8,
          ),
          child: TextField(
            key: const Key('species_filter_sheet_region_search'),
            controller: _regionSearchController,
            decoration: InputDecoration(
              hintText: context.loc.regionPickerSearchHint,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _regionSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _regionSearchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
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
              : ListView(
                  children: orderedContinents
                      .map(
                        (continent) => _ContinentSection(
                          label: _continentLabel(context.loc, continent),
                          regions: grouped[continent]!,
                          selected: _selectedRegionKeys,
                          onToggle: _toggleRegion,
                        ),
                      )
                      .toList(growable: false),
                ),
        ),
      ],
    );
  }

  Widget _buildFrequencyTab(BuildContext context) {
    return ListView(
      children: TaxonomySpeciesSelectionPresenter.allFrequencyTiers
          .map(
            (tier) => CheckboxListTile(
              key: ValueKey(
                'species_filter_sheet_tier_${tier?.name ?? 'unknown'}',
              ),
              value: _selectedTiers.contains(tier),
              onChanged: (_) => _toggleTier(tier),
              title: Text(regionAbundanceLabel(context.loc, tier)),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  context.loc.taxonomySpeciesSelectionFilterTooltip,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_hasActiveFilters)
                  TextButton(
                    key: const Key('species_filter_sheet_reset_button'),
                    onPressed: _resetFilters,
                    child: Text(context.loc.speciesFilterSheetResetButton),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          TabBar(
            key: const Key('species_filter_sheet_tab_bar'),
            controller: _tabController,
            tabs: [
              Tab(text: context.loc.speciesFilterSheetRegionSection),
              Tab(text: context.loc.speciesFilterSheetFrequencySection),
            ],
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRegionTab(context),
                _buildFrequencyTab(context),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: FilledButton(
              key: const Key('species_filter_sheet_apply_button'),
              onPressed: _selectedTiers.isEmpty ? null : _apply,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(context.loc.speciesFilterSheetApplyButton),
            ),
          ),
        ],
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
