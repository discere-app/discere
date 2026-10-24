import 'package:discere/enrichment/pipeline/repository/inat_provenance_planner.dart';
import 'package:flutter_test/flutter_test.dart';

const _planner = INatProvenancePlanner();

INatProvenanceDecision _later(INatProvenanceFacts facts) =>
    _planner.decide(facts, INatProvenanceRun.later);

INatProvenanceDecision _first(INatProvenanceFacts facts) =>
    _planner.decide(facts, INatProvenanceRun.first);

/// A species with photos and names stamped [stamp].
INatProvenanceFacts _species({
  int? stamp,
  int? referenceTaxonId,
  int? cachedTaxonId,
  bool isRejected = false,
}) => INatProvenanceFacts(
  entityId: 'discere:species:1',
  referenceTaxonId: referenceTaxonId,
  cachedTaxonId: cachedTaxonId,
  isRejected: isRejected,
  photos: INatDataStamp(stamp),
  names: INatDataStamp(stamp),
);

void main() {
  group('after a reference-database update', () {
    test('keeps data stamped with the reference id', () {
      final decision = _later(_species(stamp: 10, referenceTaxonId: 10));

      expect(decision.photos, isA<KeepStoredINatData>());
      expect(decision.names, isA<KeepStoredINatData>());
      expect(decision.dropsCachedTaxonId, isFalse);
    });

    test('discards data of a taxon the species no longer maps to', () {
      final decision = _later(_species(stamp: 10, referenceTaxonId: 11));

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
    });

    test('discards data whose reference id was dropped', () {
      final decision = _later(_species(stamp: 10));

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
    });

    test('discards data of a searched taxon once the species is rejected, '
        'and its cached id with it', () {
      final decision = _later(
        _species(stamp: 10, cachedTaxonId: 10, isRejected: true),
      );

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
      expect(decision.dropsCachedTaxonId, isTrue);
    });

    test('keeps data of a searched taxon and its cached id', () {
      final decision = _later(_species(stamp: 10, cachedTaxonId: 10));

      expect(decision.photos, isA<KeepStoredINatData>());
      expect(decision.dropsCachedTaxonId, isFalse);
    });

    test('discards data of a taxon other than the cached one', () {
      final decision = _later(_species(stamp: 9, cachedTaxonId: 10));

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.dropsCachedTaxonId, isFalse);
    });

    test('discards a marker without a taxon once the reference database has '
        'one', () {
      final decision = _later(_species(referenceTaxonId: 10));

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
    });

    test('keeps a marker without a taxon while there is none', () {
      final decision = _later(_species());

      expect(decision.photos, isA<KeepStoredINatData>());
      expect(decision.names, isA<KeepStoredINatData>());
    });

    test('drops a cached id the reference database shadows, keeping the '
        'data stamped with the reference id', () {
      final sameId = _later(
        _species(stamp: 10, referenceTaxonId: 10, cachedTaxonId: 10),
      );
      final otherId = _later(
        _species(stamp: 10, referenceTaxonId: 10, cachedTaxonId: 9),
      );

      expect(sameId.photos, isA<KeepStoredINatData>());
      expect(sameId.dropsCachedTaxonId, isTrue);
      expect(otherId.photos, isA<KeepStoredINatData>());
      expect(otherId.dropsCachedTaxonId, isTrue);
    });

    test('judges photos and names apart', () {
      final decision = _later(
        const INatProvenanceFacts(
          entityId: 'discere:species:1',
          referenceTaxonId: 10,
          photos: INatDataStamp(10),
          names: INatDataStamp(9),
        ),
      );

      expect(decision.photos, isA<KeepStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
    });

    test('has no verdict for data the entity does not have', () {
      final decision = _later(
        const INatProvenanceFacts(
          entityId: 'discere:species:1',
          referenceTaxonId: 10,
          photos: INatDataStamp(10),
        ),
      );

      expect(decision.names, isNull);
    });

    test('treats the names of a higher taxon like those of a species', () {
      INatProvenanceDecision genus({
        int? referenceTaxonId,
        int? cachedTaxonId,
        bool isRejected = false,
      }) => _later(
        INatProvenanceFacts(
          entityId: 'genus:megalomma',
          referenceTaxonId: referenceTaxonId,
          cachedTaxonId: cachedTaxonId,
          isRejected: isRejected,
          names: const INatDataStamp(10),
        ),
      );

      expect(genus(referenceTaxonId: 10).names, isA<KeepStoredINatData>());
      expect(genus(cachedTaxonId: 10).names, isA<KeepStoredINatData>());
      expect(genus(referenceTaxonId: 11).names, isA<DiscardStoredINatData>());
      expect(
        genus(cachedTaxonId: 10, isRejected: true).names,
        isA<DiscardStoredINatData>(),
      );
    });
  });

  group('on the first run', () {
    test('stamps unstamped data with the reference id and drops the cached '
        'copy of it', () {
      final decision = _first(
        _species(referenceTaxonId: 10, cachedTaxonId: 10),
      );

      expect(
        decision.photos,
        isA<StampStoredINatData>().having((v) => v.taxonId, 'taxonId', 10),
      );
      expect(
        decision.names,
        isA<StampStoredINatData>().having((v) => v.taxonId, 'taxonId', 10),
      );
      expect(decision.dropsCachedTaxonId, isTrue);
    });

    test('discards unstamped data that only a cached id explains, and the '
        'id with it', () {
      final decision = _first(_species(cachedTaxonId: 10));

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
      expect(decision.dropsCachedTaxonId, isTrue);
    });

    test('stamps unstamped data with the reference id even where the cached '
        'id differs, and drops that id', () {
      final decision = _first(_species(referenceTaxonId: 10, cachedTaxonId: 9));

      expect(
        decision.photos,
        isA<StampStoredINatData>().having((v) => v.taxonId, 'taxonId', 10),
      );
      expect(decision.dropsCachedTaxonId, isTrue);
    });

    test('discards unstamped data without any id', () {
      final decision = _first(_species());

      expect(decision.photos, isA<DiscardStoredINatData>());
      expect(decision.names, isA<DiscardStoredINatData>());
    });

    test('drops a cached id without data', () {
      final decision = _first(
        const INatProvenanceFacts(entityId: 'genus:apus', cachedTaxonId: 10),
      );

      expect(decision.dropsCachedTaxonId, isTrue);
    });

    test('judges data that already carries a stamp as on any later run', () {
      expect(
        _first(_species(stamp: 10, referenceTaxonId: 10)).photos,
        isA<KeepStoredINatData>(),
      );
      expect(
        _first(_species(stamp: 10, cachedTaxonId: 10)).photos,
        isA<DiscardStoredINatData>(),
      );
    });
  });

  test('a plan collects the verdicts per entity', () {
    final plan = _planner.plan(const [
      INatProvenanceFacts(
        entityId: 'kept',
        referenceTaxonId: 1,
        photos: INatDataStamp(1),
        names: INatDataStamp(1),
      ),
      INatProvenanceFacts(
        entityId: 'unstamped',
        referenceTaxonId: 2,
        photos: INatDataStamp(null),
        names: INatDataStamp(null),
      ),
      INatProvenanceFacts(
        entityId: 'searched',
        cachedTaxonId: 3,
        photos: INatDataStamp(null),
      ),
      INatProvenanceFacts(entityId: 'genus:apus', names: INatDataStamp(null)),
    ], INatProvenanceRun.first);

    expect(plan.photosToStamp, {'unstamped': 2});
    expect(plan.photosToDiscard, {'searched'});
    expect(plan.namesToStamp, {'unstamped': 2});
    expect(plan.namesToDiscard, {'genus:apus'});
    expect(plan.cachedTaxonIdsToDrop, {'searched'});
    expect(plan.isEmpty, isFalse);
  });

  test('a plan for data that all fits is empty', () {
    final plan = _planner.plan(const [
      INatProvenanceFacts(
        entityId: 'kept',
        referenceTaxonId: 1,
        photos: INatDataStamp(1),
      ),
    ], INatProvenanceRun.later);

    expect(plan.isEmpty, isTrue);
  });
}
