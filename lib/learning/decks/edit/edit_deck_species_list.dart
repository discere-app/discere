import 'dart:async';

import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_view_model.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The species rows of the edit-deck page, as a sliver for its scroll view.
///
/// The rows come from [species], the draft the page edits, and are on screen
/// at once. What each row shows as its image is resolved here, separately and
/// afterwards: a species' own pictures are only its reference pictures, while
/// the image the user knows from the detail page may be an iNaturalist photo
/// from the cache, and either kind may already be a file on disk. A row whose
/// resolution has not arrived — or never does — shows the first reference
/// picture from the network instead.
///
/// Resolution reads the cache only. What a deck downloads is decided by the
/// consent the enrichment queue records for it, and listing a deck's species
/// must not fetch around that.
class EditDeckSpeciesList extends StatefulWidget {
  final List<Species> species;
  final Language language;

  /// Opens the species' detail page and completes once the user is back.
  final Future<void> Function(Species species) onOpen;
  final ValueChanged<Species> onRemove;

  const EditDeckSpeciesList({
    super.key,
    required this.species,
    required this.language,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  State<EditDeckSpeciesList> createState() => _EditDeckSpeciesListState();
}

class _EditDeckSpeciesListState extends State<EditDeckSpeciesList> {
  static final _log = Logger.forType(EditDeckSpeciesList);
  static const SpeciesListItemPresenter _presenter = SpeciesListItemPresenter();

  late final SpeciesMediaService _speciesMediaService;

  /// Which resolution the list is showing. Bumped by every [_resolveImages],
  /// so an answer that arrives after a newer one was started can be recognised
  /// as describing a cache state that is no longer the latest.
  int _resolveGeneration = 0;

  /// The species the latest resolution was started for. The page mutates
  /// [EditDeckSpeciesList.species] in place, so the previous widget's list is
  /// the same object and cannot tell what was added.
  Set<String> _requestedSpeciesIds = const {};

  Map<String, SpeciesWithLocalImages> _resolvedBySpeciesId = const {};

  @override
  void initState() {
    super.initState();
    _speciesMediaService = Provider.of<SpeciesMediaService>(
      context,
      listen: false,
    );
    _resolveImagesIfSpeciesAdded();
  }

  @override
  void didUpdateWidget(EditDeckSpeciesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveImagesIfSpeciesAdded();
  }

  /// Resolves the whole list again when it holds a species the latest
  /// resolution did not cover. A removed species needs none: its row is gone,
  /// and the entries of the remaining rows are still right.
  void _resolveImagesIfSpeciesAdded() {
    final hasNewSpecies = widget.species.any(
      (species) => !_requestedSpeciesIds.contains(species.id),
    );
    if (hasNewSpecies) unawaited(_resolveImages());
  }

  Future<void> _resolveImages() async {
    final generation = ++_resolveGeneration;
    // A copy, because the page can add or remove a species while the
    // resolution is running, and the service walks its input more than once.
    final species = List.of(widget.species);
    _requestedSpeciesIds = {for (final entry in species) entry.id};

    try {
      final resolved = await _speciesMediaService.resolveSpeciesFromCache(
        species,
      );
      if (!_isCurrent(generation)) return;
      setState(() {
        _resolvedBySpeciesId = {
          for (final entry in resolved) entry.species.id: entry,
        };
      });
    } catch (error) {
      // Images are garnish on a list whose job is editing the deck. The rows
      // stay as they are, on the reference picture from the network.
      _log.warn('Resolving species images failed: $error');
    }
  }

  /// Whether an answer that just came back is still the latest one asked for.
  ///
  /// Two resolutions overlap when a species is added, or the detail page is
  /// left, while an earlier one is still running. The earlier one read the
  /// cache first and may answer last; applying it then would drop the image of
  /// the species it did not know about.
  bool _isCurrent(int generation) =>
      mounted && generation == _resolveGeneration;

  Future<void> _open(Species species) async {
    await widget.onOpen(species);
    if (!mounted) return;
    // The detail page fetches iNaturalist photos live for a species that has
    // none cached, so the cache can hold more now than when the list resolved.
    await _resolveImages();
  }

  SpeciesListItemViewModel _present(Species species) {
    final resolved = _resolvedBySpeciesId[species.id];
    return resolved == null
        ? _presenter.presentSpecies(species, widget.language)
        : _presenter.presentSpeciesWithLocalImages(resolved, widget.language);
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.zero,
      sliver: SliverList.builder(
        itemCount: widget.species.length,
        itemBuilder: (context, index) {
          final s = widget.species[index];
          return SpeciesListItem(
            key: ValueKey(s.id),
            item: _present(s),
            onTap: () => _open(s),
            onDelete: () => widget.onRemove(s),
            deleteTooltip: context.loc.editRemoveTooltip,
          );
        },
      ),
    );
  }
}
