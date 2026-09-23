import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_work_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers TaxonomyWorkPlanner — which taxonomy units a set of species
/// implies, and in which order they are worth fetching. Driven directly:
/// the planner takes species and returns a plan, so none of this needs an
/// iNaturalist double or a database.
///
/// Entity keys are lower-cased by TaxonRank.entityKey, hence the spelling
/// of the expected keys below.

const _planner = TaxonomyWorkPlanner();

Species _species(
  String id, {
  required String genus,
  required String family,
  String order = 'Perciformes',
  String className = 'Actinopterygii',
  String? genusId,
}) => Species(
  id,
  id,
  'fishbase',
  '$genus $id',
  const {},
  Classification(
    genus,
    const {},
    null,
    family,
    const {},
    order,
    const {},
    className,
    const {},
    null,
    genusId: genusId,
  ),
  const [],
);

void main() {
  test('plans nothing for no species', () {
    expect(_planner.plan(const []), isEmpty);
  });

  test('covers all four ranks of a single species', () {
    final plan = _planner.plan([
      _species('a', genus: 'Amphiprion', family: 'Pomacentridae'),
    ]);

    expect(plan.map((entry) => entry.rank).toSet(), {
      'genus',
      'family',
      'order',
      'class',
    });
    expect(plan.map((entry) => entry.runtimeEntityKey), contains(
      'genus:amphiprion',
    ));
  });

  test('registers a shared taxon once, with every member species', () {
    final plan = _planner.plan([
      _species('a', genus: 'Amphiprion', family: 'Pomacentridae'),
      _species('b', genus: 'Amphiprion', family: 'Pomacentridae'),
    ]);

    final genus = plan.singleWhere(
      (entry) => entry.runtimeEntityKey == 'genus:amphiprion',
    );
    expect(genus.speciesIds, {'a', 'b'});
  });

  test('puts the most widely shared taxon first', () {
    // One family over three species, two genera under it.
    final plan = _planner.plan([
      _species('a', genus: 'Amphiprion', family: 'Pomacentridae'),
      _species('b', genus: 'Amphiprion', family: 'Pomacentridae'),
      _species('c', genus: 'Dascyllus', family: 'Pomacentridae'),
    ]);

    final genusIndex = plan.indexWhere(
      (entry) => entry.runtimeEntityKey == 'genus:dascyllus',
    );
    final familyIndex = plan.indexWhere(
      (entry) => entry.runtimeEntityKey == 'family:pomacentridae',
    );
    expect(
      familyIndex,
      lessThan(genusIndex),
      reason: 'the family covers all three species, the genus only one',
    );
  });

  test('breaks ties on the key, so the same deck plans the same way', () {
    final speciesList = [
      _species('a', genus: 'Amphiprion', family: 'Pomacentridae'),
      _species('b', genus: 'Dascyllus', family: 'Chaetodontidae'),
    ];

    final first = _planner.plan(speciesList).map((e) => e.runtimeEntityKey);
    final second = _planner.plan(speciesList).map((e) => e.runtimeEntityKey);

    expect(first, orderedEquals(second.toList()));
  });

  test('carries the reference id through when the species has one', () {
    final plan = _planner.plan([
      _species(
        'a',
        genus: 'Amphiprion',
        family: 'Pomacentridae',
        genusId: 'genus-42',
      ),
    ]);

    final genus = plan.singleWhere((entry) => entry.rank == 'genus');
    expect(genus.entityId, 'genus-42');
    expect(
      plan.singleWhere((entry) => entry.rank == 'family').entityId,
      isNull,
    );
  });

  test('every planned entry names at least one species', () {
    final plan = _planner.plan([
      _species('a', genus: 'Amphiprion', family: 'Pomacentridae'),
      _species('b', genus: 'Dascyllus', family: 'Chaetodontidae'),
    ]);

    expect(plan, isNotEmpty);
    expect(plan.every((entry) => entry.speciesIds.isNotEmpty), isTrue);
  });
}
