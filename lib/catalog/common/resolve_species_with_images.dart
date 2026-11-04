import 'package:discere/catalog/model/species_with_local_images.dart';

/// Resolves [speciesIds] to their species with the images on disk, in the
/// order given — one pass of a list that loads in two (see `WatchlistSpeciesSection`).
///
/// Handed in from the composition root rather than read from a service:
/// what fills in the images lives in `enrichment`, which `catalog` must not
/// depend on.
typedef ResolveSpeciesWithImages =
    Future<List<SpeciesWithLocalImages>> Function(Set<String> speciesIds);
