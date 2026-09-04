import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

Species _species(
  String id, {
  required String genus,
  required String epithet,
  Map<Language, List<String>> commonNames = const {},
  String? genusId,
  String? familyId,
  String? orderId,
  String? classId,
}) {
  return Species(
    id,
    id,
    'fishbase',
    epithet,
    commonNames,
    Classification(
      genus,
      const {},
      null,
      'Lamnidae',
      const {},
      'Lamniformes',
      const {},
      'Chondrichthyes',
      const {},
      null,
      genusId: genusId,
      familyId: familyId,
      orderId: orderId,
      classId: classId,
    ),
    const [],
  );
}

void main() {
  late MockTaxonomyRepository taxonomyRepository;
  late MultipleChoiceDistractorPoolService service;

  setUp(() {
    taxonomyRepository = MockTaxonomyRepository();
    service = MultipleChoiceDistractorPoolService(
      taxonomyRepository: taxonomyRepository,
    );
  });

  test(
    'does not query the reference DB when the deck-only pool already suffices',
    () async {
      final current = _species(
        'sp1',
        genus: 'Carcharodon',
        epithet: 'carcharias',
        commonNames: const {
          Language.de: ['Weißer Hai'],
        },
        genusId: 'g1',
        familyId: 'f1',
        orderId: 'o1',
        classId: 'c1',
      );
      final deckSpecies = [
        current,
        _species(
          'sp2',
          genus: 'Carcharodon',
          epithet: 'hubbelli',
          commonNames: const {
            Language.de: ['Hubbells Weißer Hai'],
          },
          genusId: 'g1',
          familyId: 'f1',
          orderId: 'o1',
          classId: 'c1',
        ),
        _species(
          'sp3',
          genus: 'Carcharodon',
          epithet: 'plicatilis',
          commonNames: const {
            Language.de: ['Plicatilis'],
          },
          genusId: 'g1',
          familyId: 'f1',
          orderId: 'o1',
          classId: 'c1',
        ),
        _species(
          'sp4',
          genus: 'Carcharodon',
          epithet: 'other',
          commonNames: const {
            Language.de: ['Vierter'],
          },
          genusId: 'g1',
          familyId: 'f1',
          orderId: 'o1',
          classId: 'c1',
        ),
      ];

      final pool = await service.buildPool(
        currentSpecies: current,
        deckSpecies: deckSpecies,
        learningMode: LearningMode.species,
        language: Language.de,
        nameType: NameType.commonName,
      );

      expect(pool, containsAll(['Hubbells Weißer Hai', 'Plicatilis', 'Vierter']));
      verifyNever(taxonomyRepository.getDescendantsOfType(any, any));
    },
  );

  test(
    'falls back to the reference DB, escalating rank by rank, when the deck '
    'pool is too small',
    () async {
      final current = _species(
        'sp1',
        genus: 'Carcharodon',
        epithet: 'carcharias',
        commonNames: const {
          Language.de: ['Weißer Hai'],
        },
        genusId: 'g1',
        familyId: 'f1',
        orderId: 'o1',
        classId: 'c1',
      );
      final deckSpecies = [current];

      when(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.species,
          argThat(
            predicate<SearchResult>(
              (r) => r.id == 'g1' && r.type == SearchEntityType.genus,
            ),
          ),
        ),
      ).thenAnswer((_) async => []);
      when(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.species,
          argThat(
            predicate<SearchResult>(
              (r) => r.id == 'f1' && r.type == SearchEntityType.family,
            ),
          ),
        ),
      ).thenAnswer(
        (_) async => [
          SearchResult(
            id: 'sp2',
            name: 'Isurus oxyrinchus',
            commonNames: const {
              Language.de: ['Kurzflossen-Mako'],
            },
            type: SearchEntityType.species,
          ),
          SearchResult(
            id: 'sp3',
            name: 'Isurus paucus',
            commonNames: const {
              Language.de: ['Langflossen-Mako'],
            },
            type: SearchEntityType.species,
          ),
          SearchResult(
            id: 'sp4',
            name: 'Isurus other',
            commonNames: const {
              Language.de: ['Dritter Mako'],
            },
            type: SearchEntityType.species,
          ),
        ],
      );

      final pool = await service.buildPool(
        currentSpecies: current,
        deckSpecies: deckSpecies,
        learningMode: LearningMode.species,
        language: Language.de,
        nameType: NameType.commonName,
      );

      expect(
        pool,
        containsAll(['Kurzflossen-Mako', 'Langflossen-Mako', 'Dritter Mako']),
      );
      // Escalation stops at family level once enough distractors are found
      // — order/class level queries are never issued.
      verifyNever(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.species,
          argThat(
            predicate<SearchResult>((r) => r.type == SearchEntityType.order),
          ),
        ),
      );
    },
  );

  test(
    'genus mode falls back to the reference DB, escalating via family/'
    'order/class',
    () async {
      final current = _species(
        'sp1',
        genus: 'Carcharodon',
        epithet: 'carcharias',
        genusId: 'g1',
        familyId: 'f1',
        orderId: 'o1',
        classId: 'c1',
      );

      when(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.genus,
          argThat(
            predicate<SearchResult>(
              (r) => r.id == 'f1' && r.type == SearchEntityType.family,
            ),
          ),
        ),
      ).thenAnswer(
        (_) async => [
          SearchResult(
            id: 'g2',
            name: 'Isurus',
            commonNames: const {
              Language.de: ['Makohaie'],
            },
            type: SearchEntityType.genus,
          ),
          SearchResult(
            id: 'g3',
            name: 'Mitsukurina',
            commonNames: const {
              Language.de: ['Kobold-Haie'],
            },
            type: SearchEntityType.genus,
          ),
          SearchResult(
            id: 'g4',
            name: 'Odontaspis',
            commonNames: const {
              Language.de: ['Sandtigerhaie'],
            },
            type: SearchEntityType.genus,
          ),
        ],
      );

      final pool = await service.buildPool(
        currentSpecies: current,
        deckSpecies: [current],
        learningMode: LearningMode.genus,
        language: Language.de,
        nameType: NameType.commonName,
      );

      expect(
        pool,
        containsAll(['Makohaie', 'Kobold-Haie', 'Sandtigerhaie']),
      );
      // Escalation stops at family level once enough distractors are found
      // — order/class level queries are never issued.
      verifyNever(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.genus,
          argThat(
            predicate<SearchResult>((r) => r.type == SearchEntityType.order),
          ),
        ),
      );
    },
  );

  test(
    'family mode falls back to the reference DB, escalating via order/class',
    () async {
      final current = _species(
        'sp1',
        genus: 'Carcharodon',
        epithet: 'carcharias',
        genusId: 'g1',
        familyId: 'f1',
        orderId: 'o1',
        classId: 'c1',
      );

      when(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.family,
          argThat(
            predicate<SearchResult>(
              (r) => r.id == 'o1' && r.type == SearchEntityType.order,
            ),
          ),
        ),
      ).thenAnswer(
        (_) async => [
          SearchResult(
            id: 'f2',
            name: 'Mitsukurinidae',
            commonNames: const {
              Language.de: ['Kobold-Haie'],
            },
            type: SearchEntityType.family,
          ),
          SearchResult(
            id: 'f3',
            name: 'Odontaspididae',
            commonNames: const {
              Language.de: ['Sandtigerhaie'],
            },
            type: SearchEntityType.family,
          ),
          SearchResult(
            id: 'f4',
            name: 'Alopiidae',
            commonNames: const {
              Language.de: ['Fuchshaie'],
            },
            type: SearchEntityType.family,
          ),
        ],
      );

      final pool = await service.buildPool(
        currentSpecies: current,
        deckSpecies: [current],
        learningMode: LearningMode.family,
        language: Language.de,
        nameType: NameType.commonName,
      );

      expect(
        pool,
        containsAll(['Kobold-Haie', 'Sandtigerhaie', 'Fuchshaie']),
      );
      // Escalation stops at order level once enough distractors are found
      // — class level queries are never issued.
      verifyNever(
        taxonomyRepository.getDescendantsOfType(
          SearchEntityType.family,
          argThat(
            predicate<SearchResult>(
              (r) => r.type == SearchEntityType.classType,
            ),
          ),
        ),
      );
    },
  );

  test('excludes the current species from reference-DB results', () async {
    final current = _species(
      'sp1',
      genus: 'Carcharodon',
      epithet: 'carcharias',
      commonNames: const {
        Language.de: ['Weißer Hai'],
      },
      genusId: 'g1',
      familyId: 'f1',
      orderId: 'o1',
      classId: 'c1',
    );

    when(
      taxonomyRepository.getDescendantsOfType(SearchEntityType.species, any),
    ).thenAnswer(
      (_) async => [
        SearchResult(
          id: 'sp1',
          name: 'Carcharodon carcharias',
          commonNames: const {
            Language.de: ['Weißer Hai'],
          },
          type: SearchEntityType.species,
        ),
      ],
    );

    final pool = await service.buildPool(
      currentSpecies: current,
      deckSpecies: [current],
      learningMode: LearningMode.species,
      language: Language.de,
      nameType: NameType.commonName,
    );

    expect(pool, isNot(contains('Weißer Hai')));
  });

  test('uses the scientific name when nameType is scientificName', () async {
    final current = _species(
      'sp1',
      genus: 'Carcharodon',
      epithet: 'carcharias',
      genusId: 'g1',
      familyId: 'f1',
      orderId: 'o1',
      classId: 'c1',
    );

    when(
      taxonomyRepository.getDescendantsOfType(
        SearchEntityType.species,
        argThat(
          predicate<SearchResult>(
            (r) => r.id == 'g1' && r.type == SearchEntityType.genus,
          ),
        ),
      ),
    ).thenAnswer(
      (_) async => [
        SearchResult(
          id: 'sp2',
          name: 'Carcharodon hubbelli',
          commonNames: const {
            Language.de: ['Hubbells Weißer Hai'],
          },
          type: SearchEntityType.species,
        ),
      ],
    );
    when(
      taxonomyRepository.getDescendantsOfType(
        SearchEntityType.species,
        argThat(
          predicate<SearchResult>((r) => r.type != SearchEntityType.genus),
        ),
      ),
    ).thenAnswer((_) async => []);

    final pool = await service.buildPool(
      currentSpecies: current,
      deckSpecies: [current],
      learningMode: LearningMode.species,
      language: Language.de,
      nameType: NameType.scientificName,
      minimumDistinctNames: 1,
    );

    expect(pool, contains('Carcharodon hubbelli'));
    expect(pool, isNot(contains('Hubbells Weißer Hai')));
  });
}
