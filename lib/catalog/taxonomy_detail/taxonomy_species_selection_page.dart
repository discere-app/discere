import 'package:discere/catalog/common/iucn_status_chip.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/iucn_status.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_species_selection_presenter.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lets the user pick which species under a taxon (genus/family/order/class)
/// to add to a deck. All species are preselected; the user can deselect a
/// few, or sort by IUCN rarity to spot threatened species quickly.
class TaxonomySpeciesSelectionPage extends StatefulWidget {
  final SearchResult taxon;
  final Future<void> Function(
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
  final _cacheRepository = ExternalIdCacheRepository();

  late final TaxonomyRepository _repository;
  bool _isLoading = true;
  List<SearchResult> _species = const [];
  Map<String, IucnStatus> _statusById = const {};
  Set<String> _selectedIds = {};
  bool _sortByRarity = false;

  @override
  void initState() {
    super.initState();
    _repository = Provider.of<TaxonomyRepository>(context, listen: false);
    _load();
  }

  Future<void> _load() async {
    final species = await _repository.getAllSpeciesUnder(widget.taxon);
    final ids = species.map((s) => s.id).toSet();
    final rawStatuses = await _cacheRepository.getRawExternalIdsForProvider(
      ids,
      ExternalIdProvider.iucnStatus,
    );
    final statusById = <String, IucnStatus>{};
    for (final entry in rawStatuses.entries) {
      final status = IucnStatus.fromRaw(entry.value);
      if (status != null) statusById[entry.key] = status;
    }
    if (!mounted) return;
    setState(() {
      _species = species;
      _statusById = statusById;
      _selectedIds = ids;
      _isLoading = false;
    });
  }

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
    setState(() {
      if (_selectedIds.length == _species.length) {
        _selectedIds = {};
      } else {
        _selectedIds = _species.map((s) => s.id).toSet();
      }
    });
  }

  void _toggleSort() {
    setState(() => _sortByRarity = !_sortByRarity);
  }

  Future<void> _handleAddToDeck() async {
    final selectedNames = _species
        .where((s) => _selectedIds.contains(s.id))
        .map((s) => s.name)
        .toSet();
    await widget.onAddToDeck(context, _selectedIds, selectedNames);
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        _species.isNotEmpty && _selectedIds.length == _species.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.loc.taxonomySpeciesSelectionTitle(_species.length),
        ),
        actions: [
          IconButton(
            key: const Key('taxonomy_species_selection_sort_toggle'),
            tooltip: _sortByRarity
                ? context.loc.taxonomySpeciesSelectionSortAlphabetical
                : context.loc.taxonomySpeciesSelectionSortByRarity,
            icon: Icon(
              _sortByRarity ? Icons.warning_amber_rounded : Icons.sort_by_alpha,
            ),
            onPressed: _isLoading ? null : _toggleSort,
          ),
          IconButton(
            key: const Key('taxonomy_species_selection_select_all_toggle'),
            tooltip: allSelected
                ? context.loc.taxonomySpeciesSelectionDeselectAll
                : context.loc.taxonomySpeciesSelectionSelectAll,
            icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
            onPressed: _isLoading ? null : _toggleSelectAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<LanguageService>(
              builder: (context, languageService, _) {
                final sorted = _selectionPresenter.sort(
                  _species,
                  _statusById,
                  byRarity: _sortByRarity,
                );
                return ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final species = sorted[index];
                    final item = _speciesListItemPresenter.presentSearchResult(
                      species,
                      languageService.getLanguage(),
                    );
                    final status = _statusById[species.id];
                    final isSelected = _selectedIds.contains(species.id);
                    return SpeciesListItem(
                      key: ValueKey(species.id),
                      item: item,
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(species.id),
                      ),
                      trailing: status != null
                          ? IucnStatusChip(status: status, compact: true)
                          : null,
                      onTap: () => _toggleSelection(species.id),
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: _isLoading
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
