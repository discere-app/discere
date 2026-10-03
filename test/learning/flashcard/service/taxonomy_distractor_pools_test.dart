import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/flashcard/service/taxonomy_distractor_pools.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// Covers TaxonomyDistractorPools — that a session's distractor pools are
/// built per taxonomic scope, on first use, and only for the scopes its cards
/// actually ask about. Every pool build is a reference-DB query in production,
/// so most of this file asserts how many of those a session pays for; the
/// last group checks, with the real pool builder, that a pool shared that
/// way still gives every card of the deck its answer options.

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
    int minimumDistinctNames = AnswerOptionsPresenter.minimumPoolSize,
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

  group('answer options for every card', () {
    late MockTaxonomyRepository taxonomyRepository;

    setUp(() {
      taxonomyRepository = MockTaxonomyRepository();
      when(
        taxonomyRepository.getDescendantsOfType(any, any),
      ).thenAnswer((_) async => []);
    });

    Species species(
      String id,
      String name, {
      required String genusId,
      String familyId = 'f1',
      String classId = 'c1',
    }) => Species(
      id,
      id,
      'fishbase',
      id,
      {
        Language.en: [name],
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
        familyId: familyId,
        orderId: 'o-$classId',
        classId: classId,
      ),
      const [],
    );

    /// The answer options each card of [deckSpecies] gets, asked in deck
    /// order through one session's pools — so later cards of a scope draw on
    /// the pool an earlier card built.
    Future<Map<String, List<String>?>> optionsPerCard(
      List<Species> deckSpecies,
    ) async {
      final pools = TaxonomyDistractorPools(
        poolService: MultipleChoiceDistractorPoolService(
          taxonomyRepository: taxonomyRepository,
        ),
        deckSpecies: deckSpecies,
        learningMode: LearningMode.species,
        nameType: NameType.commonName,
        language: Language.en,
      );
      return {
        for (final card in deckSpecies)
          card.id: const AnswerOptionsPresenter()
              .buildOptions(
                correctLabel: const FlashcardSpeciesPresenter()
                    .present(card, Language.en)
                    .identity
                    .primaryName,
                namePool: await pools.poolFor(card),
              )
              ?.map((option) => option.label)
              .toList(),
      };
    }

    test(
      'a card whose name is in the pool another card of its scope built '
      'still gets its options',
      () async {
        final options = await optionsPerCard([
          species('sp1', 'Blacktip shark', genusId: 'g1'),
          species('sp2', 'Silky shark', genusId: 'g1'),
          species('sp3', 'Dusky shark', genusId: 'g1'),
          species('sp4', 'Spinner shark', genusId: 'g1'),
        ]);

        expect(options['sp2'], hasLength(4));
        expect(
          options['sp2'],
          containsAll(['Blacktip shark', 'Dusky shark', 'Spinner shark']),
        );
      },
    );

    test(
      'a card whose species the reference database names differently is not '
      'offered that name as a wrong answer',
      () async {
        when(
          taxonomyRepository.getDescendantsOfType(
            SearchEntityType.species,
            argThat(predicate<SearchResult>((scope) => scope.id == 'g1')),
          ),
        ).thenAnswer(
          (_) async => [
            SearchResult(
              id: 'silky',
              name: 'Carcharhinus falciformis',
              commonNames: const {
                Language.en: ['Sickle shark'],
              },
              type: SearchEntityType.species,
            ),
            SearchResult(
              id: 'blacktip-reef',
              name: 'Carcharhinus melanopterus',
              commonNames: const {
                Language.en: ['Blacktip reef shark'],
              },
              type: SearchEntityType.species,
            ),
          ],
        );

        // The blacktip card builds the genus pool; the silky card reuses it.
        final options = await optionsPerCard([
          species('blacktip', 'Blacktip shark', genusId: 'g1'),
          species('silky', 'Silky shark', genusId: 'g1'),
          species(
            'cod',
            'Atlantic cod',
            genusId: 'g7',
            familyId: 'f7',
            classId: 'c7',
          ),
        ]);

        expect(options['silky'], isNot(contains('Sickle shark')));
        expect(
          options['silky'],
          unorderedEquals([
            'Silky shark',
            'Blacktip shark',
            'Blacktip reef shark',
            'Atlantic cod',
          ]),
        );
      },
    );

    test(
      'every card of a deck with enough distinct names gets four options, '
      'an isolated species and one sharing its name with a relative included',
      () async {
        when(
          taxonomyRepository.getDescendantsOfType(
            SearchEntityType.species,
            argThat(predicate<SearchResult>((scope) => scope.id == 'g1')),
          ),
        ).thenAnswer(
          (_) async => [
            SearchResult(
              id: 'relative',
              name: 'Carcharhinus relative',
              commonNames: const {
                Language.en: ['Blacktip shark'],
              },
              type: SearchEntityType.species,
            ),
          ],
        );
        final deckSpecies = [
          species(
            'octopus',
            'Giant Pacific octopus',
            genusId: 'g9',
            familyId: 'f9',
            classId: 'c9',
          ),
          species('blacktip', 'Blacktip shark', genusId: 'g1'),
          species('mako', 'Shortfin mako', genusId: 'g2'),
          species('hammerhead', 'Great hammerhead', genusId: 'g3'),
        ];

        final options = await optionsPerCard(deckSpecies);

        for (final card in deckSpecies) {
          expect(options[card.id], hasLength(4), reason: card.id);
          expect(options[card.id]!.toSet(), hasLength(4), reason: card.id);
        }
      },
    );
  });
}
