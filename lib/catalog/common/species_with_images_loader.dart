import 'package:discere/catalog/common/resolve_species_with_images.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

/// The species a list on screen shows, with their pictures, for a set of
/// species ids that can change while the list is open.
///
/// Loads in two passes, because the two differ by orders of magnitude: what is
/// already on disk comes back in a few queries, while fetching the missing
/// images is bounded by the network and by iNaturalist's rate limit. The list
/// therefore renders from `resolveFromCache` and adopts `resolveWithDownload`'s
/// result whenever it arrives. Both passes return the same species in the same
/// order, so adopting the second one fills in images without resorting the
/// list.
///
/// A plain object rather than a `State` mixin, so that its rules — above all
/// which result may still be applied — can be tested without a widget, and so
/// that the owning `State` keeps nothing of it but one field. The owner calls
/// [dispose] from its own `dispose`, and rebuilds in [onChanged].
class SpeciesWithImagesLoader {
  final ResolveSpeciesWithImages _resolveFromCache;
  final ResolveSpeciesWithImages _resolveWithDownload;

  /// Called after [species] or [loadError] changed; the owner rebuilds.
  final VoidCallback _onChanged;
  final ScopedLogger _log;

  /// Which load the list is showing. Bumped by every [load] and by
  /// [removeOptimistically], so a result that arrives after the set of species
  /// has changed can be recognised as belonging to a set no longer on screen.
  int _generation = 0;
  bool _disposed = false;

  List<SpeciesWithLocalImages>? _species;
  Object? _loadError;

  SpeciesWithImagesLoader({
    required ResolveSpeciesWithImages resolveFromCache,
    required ResolveSpeciesWithImages resolveWithDownload,
    required VoidCallback onChanged,
    required ScopedLogger log,
  }) : _resolveFromCache = resolveFromCache,
       _resolveWithDownload = resolveWithDownload,
       _onChanged = onChanged,
       _log = log;

  /// The species on screen, or null while the first load is still running.
  /// A reload keeps the previous species visible instead of dropping back to
  /// a spinner and tearing the whole list down (which would also visually
  /// undo the Dismissible swipe animation that just ran).
  List<SpeciesWithLocalImages>? get species => _species;

  /// Why the species could not be loaded from the cache. Only shown while
  /// [species] is still null.
  Object? get loadError => _loadError;

  Future<void> load(Set<String> speciesIds) async {
    final generation = ++_generation;

    try {
      final cached = await _resolveFromCache(speciesIds);
      if (!_isCurrent(generation)) return;
      _species = cached;
      _loadError = null;
      _onChanged();
    } catch (error, stackTrace) {
      _log.warn('Species load failed', error: error, stackTrace: stackTrace);
      if (!_isCurrent(generation)) return;
      _loadError = error;
      _onChanged();
      return;
    }

    try {
      final withImages = await _resolveWithDownload(speciesIds);
      if (!_isCurrent(generation)) return;
      _species = withImages;
      _onChanged();
    } catch (error, stackTrace) {
      // The cached species are already on screen and usable. A failed image
      // fetch must not replace them with an error message.
      _log.warn(
        'Species image download failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Takes [speciesId] off the screen right away, ahead of the reload its
  /// removal from the underlying store starts.
  ///
  /// Invalidates whatever load is still in flight first: it was started for a
  /// set that still contained this species, so its result would put the
  /// removed entry back — which also crashes the Dismissible that was already
  /// dismissed. Waiting for the reload to bump the generation is too late: the
  /// store's notification arrives a frame later, and a pending result can land
  /// first.
  void removeOptimistically(String speciesId) {
    _generation++;
    _species = _species
        ?.where((entry) => entry.species.id != speciesId)
        .toList();
    _onChanged();
  }

  /// Drops every result still in flight.
  void dispose() => _disposed = true;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
}
