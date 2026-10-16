import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:flutter_test/flutter_test.dart';

/// A species' chain as the reference database may hand it over: [genus] and
/// [family] `null` where the chain breaks off, [placeholderRanks] where a
/// source holds a rank placeholder.
Species _species({
  String? genus = 'Kynaria',
  String? family = 'Facelinidae',
  Set<TaxonRank> placeholderRanks = const {},
}) => Species(
  'sp1',
  'sp1',
  'sealifebase',
  'cynara',
  const {},
  Classification(
    genus,
    const {},
    null,
    family,
    const {},
    family == null ? null : 'Nudibranchia',
    const {},
    family == null ? null : 'Gastropoda',
    const {},
    null,
    placeholderRanks: placeholderRanks,
  ),
  const [],
);

void main() {
  test('every species has an answer in species mode', () {
    for (final species in [
      _species(),
      _species(genus: null, family: null),
      _species(placeholderRanks: const {TaxonRank.family}),
    ]) {
      expect(LearningMode.species.hasNoAnswerFor(species), isFalse);
    }
  });

  test('a species without a genus has no answer in genus mode, and none in '
      'family mode, which its chain no longer reaches', () {
    final species = _species(genus: null, family: null);

    expect(LearningMode.genus.hasNoAnswerFor(species), isTrue);
    expect(LearningMode.family.hasNoAnswerFor(species), isTrue);
  });

  test('a missing or placeholder family leaves no answer in family mode, '
      'and the genus still one in genus mode', () {
    for (final species in [
      _species(family: null),
      _species(placeholderRanks: const {TaxonRank.family}),
    ]) {
      expect(LearningMode.family.hasNoAnswerFor(species), isTrue);
      expect(LearningMode.genus.hasNoAnswerFor(species), isFalse);
    }
  });

  test('the check on unassigned ranks alone agrees with the one on the '
      'species', () {
    final species = _species(family: null);

    for (final mode in LearningMode.values) {
      expect(
        mode.hasNoAnswerGiven(species.classification.unassignedRanks),
        mode.hasNoAnswerFor(species),
        reason: '$mode',
      );
    }
  });
}
