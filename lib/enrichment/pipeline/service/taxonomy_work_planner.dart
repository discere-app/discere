import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';

/// One taxonomy unit a set of species implies, and which of those species
/// sit under it.
///
/// The work key is missing on purpose: assigning one needs a lookup, and
/// everything up to that point follows from the species alone.
class TaxonomyPlanEntry {
  /// Identifies the taxon across the runtime tables, e.g. `genus:Amphiprion`.
  final String runtimeEntityKey;

  final String rank;
  final String scientificName;

  /// The reference database's id for this taxon, when it has one. Absent for
  /// a taxon that only exists in the runtime tables.
  final String? entityId;

  /// The species from the planned set that belong to this taxon.
  final Set<String> speciesIds;

  const TaxonomyPlanEntry({
    required this.runtimeEntityKey,
    required this.rank,
    required this.scientificName,
    required this.entityId,
    required this.speciesIds,
  });
}

/// Works out which taxonomy units a set of species implies, and in which
/// order they are worth fetching.
///
/// Pure: species in, plan out. No repository, no iNaturalist, no clock —
/// which is the point. The ordering rule below is the kind of thing that
/// wants a test, and while it lived inside the fetching service it needed
/// iNaturalist doubles to reach.
class TaxonomyWorkPlanner {
  const TaxonomyWorkPlanner();

  /// Every genus, family, order and class the species belong to, most
  /// widely-shared first. A rank placeholder of the sources ("Not assigned")
  /// is left out: it is no taxon iNaturalist could name, and all of a
  /// rank's placeholders would share the one entity key `family:not
  /// assigned`.
  ///
  /// The order is what makes a partial run useful: a genus covering eleven
  /// of the deck's species earns its request more than one covering a
  /// single species, so if the run is cancelled or rate-limited half way,
  /// what did get fetched is what most cards needed. Ties break on the key
  /// so two runs over the same deck plan the same way.
  List<TaxonomyPlanEntry> plan(List<Species> speciesList) {
    final targets = _targets(speciesList);
    final membership = _membership(speciesList);

    final entityKeys = membership.keys.toList(growable: false);
    entityKeys.sort((left, right) {
      final byCount = (membership[right]?.length ?? 0).compareTo(
        membership[left]?.length ?? 0,
      );
      return byCount != 0 ? byCount : left.compareTo(right);
    });

    return [
      for (final entityKey in entityKeys)
        if (targets[entityKey] case final target?)
          TaxonomyPlanEntry(
            runtimeEntityKey: entityKey,
            rank: target.rank,
            scientificName: target.scientificName,
            entityId: target.entityId,
            speciesIds: membership[entityKey] ?? const <String>{},
          ),
    ];
  }

  /// Each taxon's rank and name, keyed the way the runtime tables key it.
  /// A taxon reached from several species is registered once.
  Map<String, ({String rank, String scientificName, String? entityId})>
  _targets(List<Species> speciesList) {
    final targets =
        <String, ({String rank, String scientificName, String? entityId})>{};
    for (final species in speciesList) {
      final classification = species.classification;
      for (final rank in TaxonRank.values) {
        // Neither a placeholder nor a missing rank names a taxon to enrich.
        final scientificName = classification.scientificNameAt(rank);
        if (scientificName == null || classification.isPlaceholder(rank)) {
          continue;
        }
        targets[rank.entityKey(scientificName)] = (
          rank: rank.rankName,
          scientificName: scientificName,
          entityId: classification.idAt(rank),
        );
      }
    }
    return targets;
  }

  /// Which species sit under each taxon — the counts the ordering above
  /// rests on, and what a caller needs to know which cards a finished fetch
  /// just improved.
  Map<String, Set<String>> _membership(List<Species> speciesList) {
    final membership = <String, Set<String>>{};
    for (final species in speciesList) {
      final classification = species.classification;
      for (final rank in TaxonRank.values) {
        final scientificName = classification.scientificNameAt(rank);
        if (scientificName == null || classification.isPlaceholder(rank)) {
          continue;
        }
        membership
            .putIfAbsent(rank.entityKey(scientificName), () => <String>{})
            .add(species.id);
      }
    }
    return membership;
  }
}
