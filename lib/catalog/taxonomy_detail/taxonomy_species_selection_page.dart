import 'package:discere/catalog/common/region_abundance_label.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/taxonomy_detail/species_filter_sheet.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_species_selection_presenter.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/extensions/color_contrast_extension.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lets the user pick which species under a taxon (genus/family/order/class)
/// to add to a deck. All species are preselected; the user can deselect a
/// few, or filter down to species that occur in one or more chosen regions
/// (e.g. "stony corals found in Egypt"), sorted by how commonly they're
/// sighted there.
class TaxonomySpeciesSelectionPage extends StatefulWidget {
  final SearchResult taxon;
  final Future<bool> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )
  onAddToDeck;

  const TaxonomySpeciesSelectionPage({
    super.key,
    required this.taxon,
    required this.onAddToDeck,
  });

  @override
  State<TaxonomySpeciesSelectionPage> createState() =>
      _TaxonomySpeciesSelectionPageState();
}

class _TaxonomySpeciesSelectionPageState
    extends State<TaxonomySpeciesSelectionPage> {
  static const _speciesListItemPresenter = SpeciesListItemPresenter();
  static const _selectionPresenter = TaxonomySpeciesSelectionPresenter();

  late final TaxonomyRepository _repository;
  bool _isLoading = true;
  bool _isLoadingRegionFilter = false;
  List<SearchResult> _species = const [];
  Set<String> _speciesIds = const {};
  List<String> _availableRegionKeys = const [];
  Set<String> _selectedRegionKeys = const {};
  Map<String, List<String>> _abundanceBySpeciesId = const {};
  Map<String, List<String>> _globalAbundanceBySpeciesId = const {};
  Set<RegionAbundance?> _selectedTiers =
      TaxonomySpeciesSelectionPresenter.allFrequencyTiers;
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<TaxonomyRepository>(context, listen: false);
    _load();
  }

  Future<void> _load() async {
    final species = await _repository.getAllSpeciesUnder(widget.taxon);
    final ids = species.map((s) => s.id).toSet();
    final regionKeys = await _repository.getAvailableRegions(ids);
    final globalAbundance = await _repository.getAllAbundanceRawValues(ids);
    if (!mounted) return;
    setState(() {
      _species = species;
      _speciesIds = ids;
      _availableRegionKeys = regionKeys;
      _globalAbundanceBySpeciesId = globalAbundance;
      _selectedIds = ids;
      _isLoading = false;
    });
  }

  /// Abundance data relevant to the current filter state: per-region when a
  /// region filter is active (so sorting/filtering reflects those regions
  /// specifically), otherwise across every country the species is recorded
  /// in (so the frequency filter still works with no region chosen).
  Map<String, List<String>> get _effectiveAbundance =>
      _selectedRegionKeys.isEmpty
      ? _globalAbundanceBySpeciesId
      : _abundanceBySpeciesId;

  bool get _frequencyFilterActive =>
      _selectedTiers.length <
      TaxonomySpeciesSelectionPresenter.allFrequencyTiers.length;

  List<SearchResult> get _displayedSpecies => _selectionPresenter.filterAndSort(
    _species,
    regionFilterActive: _selectedRegionKeys.isNotEmpty,
    abundanceRawValuesBySpeciesId: _effectiveAbundance,
    selectedTiers: _selectedTiers,
  );

  void _toggleSelection(String speciesId) {
    setState(() {
      if (_selectedIds.contains(speciesId)) {
        _selectedIds.remove(speciesId);
      } else {
        _selectedIds.add(speciesId);
      }
    });
  }

  void _toggleSelectAll() {
    final displayedIds = _displayedSpecies.map((s) => s.id).toSet();
    final allSelected =
        displayedIds.isNotEmpty && displayedIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(displayedIds);
      } else {
        _selectedIds.addAll(displayedIds);
      }
    });
  }

  Future<void> _openFilterSheet() async {
    final result = await showSpeciesFilterSheet(
      context,
      availableRegionKeys: _availableRegionKeys,
      initiallySelectedRegionKeys: _selectedRegionKeys,
      initiallySelectedTiers: _selectedTiers,
    );
    if (result == null || !mounted) return;

    if (result.regionKeys.isEmpty) {
      setState(() {
        _selectedRegionKeys = const {};
        _abundanceBySpeciesId = const {};
        _selectedTiers = result.tiers;
        _selectedIds = _displayedSpecies.map((s) => s.id).toSet();
      });
      return;
    }

    if (setEquals(result.regionKeys, _selectedRegionKeys)) {
      setState(() {
        _selectedTiers = result.tiers;
        _selectedIds = _displayedSpecies.map((s) => s.id).toSet();
      });
      return;
    }

    setState(() {
      _selectedRegionKeys = result.regionKeys;
      _isLoadingRegionFilter = true;
    });
    final abundance = await _repository.getAbundanceRawValuesByRegion(
      _speciesIds,
      result.regionKeys,
    );
    if (!mounted) return;
    setState(() {
      _abundanceBySpeciesId = abundance;
      _selectedTiers = result.tiers;
      _isLoadingRegionFilter = false;
      _selectedIds = _displayedSpecies.map((s) => s.id).toSet();
    });
  }

  Future<void> _handleAddToDeck() async {
    final selectedNames = _species
        .where((s) => _selectedIds.contains(s.id))
        .map((s) => s.name)
        .toSet();
    final added = await widget.onAddToDeck(context, _selectedIds, selectedNames);
    if (added && mounted) Navigator.of(context).pop();
  }

  int get _activeFilterCount =>
      (_selectedRegionKeys.isNotEmpty ? 1 : 0) +
      (_frequencyFilterActive ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final displayed = _isLoading ? const <SearchResult>[] : _displayedSpecies;
    final displayedIds = displayed.map((s) => s.id).toSet();
    final allSelected =
        displayedIds.isNotEmpty && displayedIds.every(_selectedIds.contains);
    final isBusy = _isLoading || _isLoadingRegionFilter;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.taxonomySpeciesSelectionTitle(displayed.length)),
        actions: [
          IconButton(
            key: const Key('taxonomy_species_selection_filter_button'),
            tooltip: context.loc.taxonomySpeciesSelectionFilterTooltip,
            icon: _activeFilterCount == 0
                ? const Icon(Icons.filter_list)
                : Badge(
                    label: Text('$_activeFilterCount'),
                    child: const Icon(Icons.filter_list),
                  ),
            onPressed: _isLoading ? null : _openFilterSheet,
          ),
          IconButton(
            key: const Key('taxonomy_species_selection_select_all_toggle'),
            tooltip: allSelected
                ? context.loc.taxonomySpeciesSelectionDeselectAll
                : context.loc.taxonomySpeciesSelectionSelectAll,
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
            onPressed: isBusy ? null : _toggleSelectAll,
          ),
        ],
      ),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : Consumer<LanguageService>(
              builder: (context, languageService, _) {
                final resolveThumbnailUrl = context
                    .read<INaturalistService>()
                    .fetchThumbnailUrl;
                if (displayed.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s24),
                      child: Text(
                        _selectedRegionKeys.isEmpty
                            ? context.loc.taxonomySpeciesSelectionNoFrequencyMatches
                            : context.loc.taxonomySpeciesSelectionNoRegionMatches,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: displayed.length,
                  itemBuilder: (context, index) {
                    final species = displayed[index];
                    final item = _speciesListItemPresenter.presentSearchResult(
                      species,
                      languageService.getLanguage(),
                    );
                    final isSelected = _selectedIds.contains(species.id);
                    final showAbundance =
                        _selectedRegionKeys.isNotEmpty || _frequencyFilterActive;
                    final abundance = showAbundance
                        ? _selectionPresenter.bestAbundanceFor(
                            _effectiveAbundance[species.id] ?? const [],
                          )
                        : null;
                    return SpeciesListItem(
                      key: ValueKey(species.id),
                      item: item,
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(species.id),
                          ),
                          SearchResultThumbnail(
                            scientificName: species.name,
                            resolveThumbnailUrl: resolveThumbnailUrl,
                            size: 48,
                            accentColor: Theme.of(context).colorScheme.tertiary,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.tertiaryContainer.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ],
                      ),
                      trailing: showAbundance
                          ? _AbundanceChip(abundance: abundance)
                          : null,
                      onTap: () => _toggleSelection(species.id),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: isBusy
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: FilledButton.icon(
                  key: const Key('taxonomy_species_selection_add_button'),
                  onPressed: _selectedIds.isEmpty ? null : _handleAddToDeck,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(
                    context.loc.taxonomySpeciesSelectionAddButton(
                      _selectedIds.length,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _AbundanceChip extends StatelessWidget {
  final RegionAbundance? abundance;

  const _AbundanceChip({required this.abundance});

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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: 3),
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
