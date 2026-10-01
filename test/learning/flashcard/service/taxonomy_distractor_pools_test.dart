import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/flashcard/service/taxonomy_distractor_pools.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers TaxonomyDistractorPools — that a session's distractor pools are
/// built per taxonomic scope, on first use, and only for the scopes its cards
/// actually ask about. Every pool build is a reference-DB query in production,
/// so what this file really asserts is how many of those a session pays for.

/// Records the species each pool was built for, standing in for the
/// reference-DB-backed builder.
class _RecordingPoolService extends Fake
    implements MultipleChoiceDistractorPoolService {
  final List<String> builtFor = [];

  @override
  Future<List<String>> buildPool({
    required Species currentSpecies,
    required List<Species> deckSpecies,
    required LearningMode learningMode,
    required Language language,
    required NameType nameType,
    int minimumDistinctNames = 3,
  }) async {
    builtFor.add(currentSpecies.id);
    return ['pool of ${currentSpecies.classification.genusId}'];
  }
}

Species _species(String id, {String? genusId = 'genus-1'}) => Species(
  id,
  id,
  'fishbase',
  'Scientific $id',
  {
    Language.en: ['Name $id'],
  },
  Classification(
    'Genus',
    const {},
    null,
    'Family',
    const {},
    'Order',
    const {},
    'Class',
    const {},
    null,
    genusId: genusId,
    familyId: 'family-1',
    orderId: 'order-1',
  ),
  const [],
);

TaxonomyDistractorPools _pools(
  _RecordingPoolService poolService,
  List<Species> deckSpecies, {
  LearningMode learningMode = LearningMode.species,
}) => TaxonomyDistractorPools(
  poolService: poolService,
  deckSpecies: deckSpecies,
  learningMode: learningMode,
  nameType: NameType.commonName,
  language: Language.en,
);

void main() {
  late _RecordingPoolService poolService;

  setUp(() => poolService = _RecordingPoolService());

  test('builds a scope pool on first use, not before', () async {
    final species = _species('sp1');
    final pools = _pools(poolService, [species]);

    expect(poolService.builtFor, isEmpty);

    expect(await pools.poolFor(species), ['pool of genus-1']);
    expect(poolService.builtFor, ['sp1']);
  });

  test('reuses one pool for every card in the same scope', () async {
    final deckSpecies = [_species('sp1'), _species('sp2'), _species('sp3')];
    final pools = _pools(poolService, deckSpecies);

    for (final species in deckSpecies) {
      expect(await pools.poolFor(species), ['pool of genus-1']);
    }

    expect(poolService.builtFor, ['sp1']);
  });

  test('builds nothing for a scope no card asked about', () async {
    final asked = _species('sp1');
    final untouched = _species('sp2', genusId: 'genus-2');
    final pools = _pools(poolService, [asked, untouched]);

    await pools.poolFor(asked);

    expect(poolService.builtFor, ['sp1']);
  });

  test('builds one pool per distinct scope', () async {
    final first = _species('sp1');
    final second = _species('sp2', genusId: 'genus-2');
    final pools = _pools(poolService, [first, second]);

    expect(await pools.poolFor(first), ['pool of genus-1']);
    expect(await pools.poolFor(second), ['pool of genus-2']);

    expect(poolService.builtFor, ['sp1', 'sp2']);
  });

  test(
    'a species without a scope id draws from the whole deck instead',
    () async {
      final unscoped = _species('sp1', genusId: null);
      final pools = _pools(poolService, [unscoped, _species('sp2')]);

      expect(await pools.poolFor(unscoped), ['Name sp1', 'Name sp2']);
      expect(poolService.builtFor, isEmpty);
    },
  );

  test('genus mode scopes by family instead of genus', () async {
    final first = _species('sp1');
    final second = _species('sp2', genusId: 'genus-2');
    final pools = _pools(
      poolService,
      [first, second],
      learningMode: LearningMode.genus,
    );

    await pools.poolFor(first);
    await pools.poolFor(second);

    // Both species sit in family-1, so genus mode sees a single scope even
    // though their genera differ.
    expect(poolService.builtFor, ['sp1']);
  });
}
