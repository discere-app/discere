/// Decides which of the iNaturalist data stored for an entity still belongs
/// to the taxon the entity maps to, after the reference database changed.
///
/// Photos (`inat_photo_cache`) and common names (`runtime_common_names`)
/// carry the iNat taxon id they were fetched from. A new reference database
/// can map an entity to another taxon, drop its mapping, or reject the taxa
/// of its name; then the stored data is of another organism and goes, so
/// that enrichment fetches it again under the checked resolution
/// (docs/enrichment.md, "Herkunft der iNat-Daten").
///
/// Kept apart from the reads and writes so the rules can be stated against
/// plain values. The repository applies the whole plan in one transaction.
library;

/// Which run of the reconciliation this is on the installation.
enum INatProvenanceRun {
  /// The first one. Rows without a stamp may come from an app version that
  /// did not stamp, and are taken as fetched with the reference database
  /// installed now — as a rule they were, though an older app version
  /// installs any newer reference database of a schema it supports, and
  /// data from before such an install is stamped wrongly (docs/enrichment.md,
  /// "Bekannte Lücke: Daten aus einer noch älteren Referenz-DB"). Cached ids
  /// from that time were found by a search that checked no phylum and fell
  /// back on the first result, so none of them is trusted.
  first,

  /// Any later one: every row carries its stamp, a null one meaning the
  /// marker of a search that found no taxon, and a cached id was found by
  /// the checked search.
  later,
}

/// The stamp the stored photos or names of an entity carry: the iNat taxon
/// they were fetched from. Null on a marker of a search that found no taxon,
/// and on any row written without a stamp.
final class INatDataStamp {
  final int? taxonId;

  const INatDataStamp(this.taxonId);
}

/// What is on record for one entity: a species id, or the name key of a
/// higher taxon (`genus:megalomma`) — the key of `entity_external_ids`.
final class INatProvenanceFacts {
  final String entityId;

  /// The id in the reference database's `entity_external_ids`.
  final int? referenceTaxonId;

  /// The id in `external_identifier_cache`, found by a runtime search.
  final int? cachedTaxonId;

  /// Whether the reference database rejects every taxon of the entity's
  /// name (`entity_external_id_rejections`).
  final bool isRejected;

  /// The stamp of the stored photos, null when there are none.
  final INatDataStamp? photos;

  /// The stamp of the stored common names, null when there are none.
  final INatDataStamp? names;

  const INatProvenanceFacts({
    required this.entityId,
    this.referenceTaxonId,
    this.cachedTaxonId,
    this.isRejected = false,
    this.photos,
    this.names,
  });
}

/// What becomes of one entity's stored photos or names.
sealed class StoredINatDataVerdict {
  const StoredINatDataVerdict();
}

/// They belong to the taxon the entity maps to.
final class KeepStoredINatData extends StoredINatDataVerdict {
  const KeepStoredINatData();
}

/// Written without a stamp, from [taxonId]: they get it.
final class StampStoredINatData extends StoredINatDataVerdict {
  final int taxonId;

  const StampStoredINatData(this.taxonId);
}

/// From another taxon, or from none where the entity now has one: they go,
/// and enrichment fetches them again.
final class DiscardStoredINatData extends StoredINatDataVerdict {
  const DiscardStoredINatData();
}

/// The verdicts for one entity, null for data it does not have.
final class INatProvenanceDecision {
  final StoredINatDataVerdict? photos;
  final StoredINatDataVerdict? names;

  /// Whether its `external_identifier_cache` id goes.
  final bool dropsCachedTaxonId;

  const INatProvenanceDecision({
    this.photos,
    this.names,
    required this.dropsCachedTaxonId,
  });
}

/// Everything the repository changes, keyed by entity id.
final class INatProvenancePlan {
  final Map<String, int> photosToStamp;
  final Set<String> photosToDiscard;
  final Map<String, int> namesToStamp;
  final Set<String> namesToDiscard;
  final Set<String> cachedTaxonIdsToDrop;

  const INatProvenancePlan({
    required this.photosToStamp,
    required this.photosToDiscard,
    required this.namesToStamp,
    required this.namesToDiscard,
    required this.cachedTaxonIdsToDrop,
  });

  bool get isEmpty =>
      photosToStamp.isEmpty &&
      photosToDiscard.isEmpty &&
      namesToStamp.isEmpty &&
      namesToDiscard.isEmpty &&
      cachedTaxonIdsToDrop.isEmpty;
}

class INatProvenancePlanner {
  const INatProvenancePlanner();

  INatProvenancePlan plan(
    Iterable<INatProvenanceFacts> entities,
    INatProvenanceRun run,
  ) {
    final photosToStamp = <String, int>{};
    final photosToDiscard = <String>{};
    final namesToStamp = <String, int>{};
    final namesToDiscard = <String>{};
    final cachedTaxonIdsToDrop = <String>{};
    for (final facts in entities) {
      final decision = decide(facts, run);
      switch (decision.photos) {
        case StampStoredINatData(:final taxonId):
          photosToStamp[facts.entityId] = taxonId;
        case DiscardStoredINatData():
          photosToDiscard.add(facts.entityId);
        case KeepStoredINatData() || null:
          break;
      }
      switch (decision.names) {
        case StampStoredINatData(:final taxonId):
          namesToStamp[facts.entityId] = taxonId;
        case DiscardStoredINatData():
          namesToDiscard.add(facts.entityId);
        case KeepStoredINatData() || null:
          break;
      }
      if (decision.dropsCachedTaxonId) cachedTaxonIdsToDrop.add(facts.entityId);
    }
    return INatProvenancePlan(
      photosToStamp: photosToStamp,
      photosToDiscard: photosToDiscard,
      namesToStamp: namesToStamp,
      namesToDiscard: namesToDiscard,
      cachedTaxonIdsToDrop: cachedTaxonIdsToDrop,
    );
  }

  /// Stored data is kept when its stamp is the taxon the entity maps to
  /// now — the reference database's id, else a cached one — and goes
  /// otherwise; a marker without a taxon stays only while there is none.
  ///
  /// The order is the resolvers' (`INatTaxonResolver.knownTaxonId`,
  /// `HigherTaxonIdResolver.knownTaxonId`): reference database before cache.
  /// They read the cache before asking about a rejection, which holds only
  /// because a cached id of a rejected entity goes here; so does one the
  /// reference database shadows, which nothing reads and which would come
  /// back into force if the reference database dropped its id.
  INatProvenanceDecision decide(
    INatProvenanceFacts facts,
    INatProvenanceRun run,
  ) {
    final referenceTaxonId = facts.referenceTaxonId;
    final trustsCache = run == INatProvenanceRun.later && !facts.isRejected;
    final expectedTaxonId =
        referenceTaxonId ?? (trustsCache ? facts.cachedTaxonId : null);

    StoredINatDataVerdict? verdictFor(INatDataStamp? stored) {
      if (stored == null) return null;
      final stamp = stored.taxonId;
      if (run == INatProvenanceRun.first && stamp == null) {
        return referenceTaxonId != null
            ? StampStoredINatData(referenceTaxonId)
            : const DiscardStoredINatData();
      }
      return stamp == expectedTaxonId
          ? const KeepStoredINatData()
          : const DiscardStoredINatData();
    }

    return INatProvenanceDecision(
      photos: verdictFor(facts.photos),
      names: verdictFor(facts.names),
      dropsCachedTaxonId:
          facts.cachedTaxonId != null &&
          (referenceTaxonId != null || !trustsCache),
    );
  }
}
