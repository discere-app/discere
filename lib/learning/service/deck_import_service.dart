import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/util/json_export_util.dart';

class DeckImportResult {
  final List<String> importedDeckIds;
  final Map<String, String> imageUrlByDeckId;
  /// Species names that could not be resolved locally, grouped by deck ID.
  /// These will be resolved in the background via iNaturalist.
  final Map<String, List<String>> unresolvedNamesByDeckId;
  final String? lastError;
  final int attemptedCount;

  const DeckImportResult({
    required this.importedDeckIds,
    required this.imageUrlByDeckId,
    this.unresolvedNamesByDeckId = const {},
    required this.lastError,
    required this.attemptedCount,
  });

  int get successCount => importedDeckIds.length;
  bool get hasSuccess => importedDeckIds.isNotEmpty;
  bool get hasUnresolvedNames =>
      unresolvedNamesByDeckId.values.any((names) => names.isNotEmpty);

  /// Flat list of all unresolved names across decks, for display purposes.
  List<String> get unresolvedNames =>
      unresolvedNamesByDeckId.values.expand((names) => names).toList();

  bool get allSucceeded => successCount == attemptedCount;
}

class DeckImportService {
  static final _log = Logger.forType(DeckImportService);
  final DecksService _decksService;
  final SpeciesRepository _speciesRepository;
  final INaturalistService? _iNatService;

  DeckImportService(
    this._decksService,
    this._speciesRepository, {
    INaturalistService? iNatService,
  }) : _iNatService = iNatService;

  Future<DeckImportResult> importJson(String jsonText) async {
    try {
      final deck = CreateDeck.fromJsonString(jsonText);
      final unresolved = await _resolveSpeciesIds(deck);
      final deckId = await _decksService.createDeck(deck);
      return DeckImportResult(
        importedDeckIds: [deckId],
        imageUrlByDeckId: {
          if (deck.imageUrl != null && deck.imageUrl!.trim().isNotEmpty)
            deckId: deck.imageUrl!.trim(),
        },
        unresolvedNamesByDeckId: {
          if (unresolved.isNotEmpty) deckId: unresolved,
        },
        lastError: null,
        attemptedCount: 1,
      );
    } catch (error) {
      return DeckImportResult(
        importedDeckIds: const [],
        imageUrlByDeckId: const {},
        lastError: error.toString(),
        attemptedCount: 1,
      );
    }
  }

  Future<String> importGzip(String gzipEncodedText) async {
    if (gzipEncodedText.trim().isEmpty) {
      throw FormatException('Empty GZIP input');
    }

    try {
      return JsonExportUtil.decode<Future<String>>(gzipEncodedText, (
        map,
      ) async {
        final deck = CreateDeck.fromJson(map);
        await _resolveSpeciesIds(deck);
        return _decksService.createDeck(deck);
      });
    } catch (error) {
      _log.warn('Error decoding GZIP deck: $error');
      rethrow;
    }
  }

  Future<String> importDeckFromSpeciesNames({
    required String name,
    required String description,
    required List<String> scientificNames,
    Language? language,
    String? coverImagePath,
  }) async {
    if (scientificNames.isEmpty) {
      final deck = CreateDeck(
        name: name,
        description: description,
        language: language,
        speciesIds: {},
      )..coverImagePath = coverImagePath;
      return _decksService.createDeck(deck);
    }

    final speciesIds = await _speciesRepository.getSpeciesIdsByFullNames(
      scientificNames,
    );

    final deck = CreateDeck(
      name: name,
      description: description,
      language: language,
      speciesIds: speciesIds,
    )..coverImagePath = coverImagePath;
    return _decksService.createDeck(deck);
  }

  Future<DeckImportResult> importDecks(List<CreateDeck> decks) async {
    if (decks.isEmpty) {
      return const DeckImportResult(
        importedDeckIds: [],
        imageUrlByDeckId: {},
        lastError: null,
        attemptedCount: 0,
      );
    }

    final importedDeckIds = <String>[];
    final imageUrlByDeckId = <String, String>{};
    final unresolvedNamesByDeckId = <String, List<String>>{};
    String? lastError;

    for (final deck in decks) {
      try {
        final importDeck = _cloneDeck(deck);
        final unresolved = await _resolveSpeciesIds(importDeck);
        final deckId = await _decksService.createDeck(importDeck);
        importedDeckIds.add(deckId);
        if (unresolved.isNotEmpty) {
          unresolvedNamesByDeckId[deckId] = unresolved;
        }
        if (importDeck.imageUrl != null &&
            importDeck.imageUrl!.trim().isNotEmpty) {
          imageUrlByDeckId[deckId] = importDeck.imageUrl!.trim();
        }
      } catch (error) {
        lastError = error.toString();
      }
    }

    return DeckImportResult(
      importedDeckIds: importedDeckIds,
      imageUrlByDeckId: imageUrlByDeckId,
      unresolvedNamesByDeckId: unresolvedNamesByDeckId,
      lastError: lastError,
      attemptedCount: decks.length,
    );
  }

  /// Returns the list of species names that could not be resolved locally.
  /// iNaturalist fallback is intentionally skipped here and handled separately
  /// by the enrichment queue so the import completes immediately.
  Future<List<String>> _resolveSpeciesIds(CreateDeck deck) async {
    final names = deck.speciesNames?.toList() ?? [];
    if (names.isEmpty) return const [];

    final resolved = <String, String>{
      ...await _speciesRepository.resolveFullNames(names),
    };

    if (resolved.isEmpty) {
      _log.warn(
        'Deck "${deck.name}": none of ${names.length} species names could be resolved locally',
      );
      return names;
    }

    final unresolved = names.where((n) => !resolved.containsKey(n)).toList();
    if (unresolved.isNotEmpty) {
      _log.debug(
        'Deck "${deck.name}": ${unresolved.length}/${names.length} species not found locally '
        '– will be resolved in background: ${unresolved.join(", ")}',
      );
    } else {
      _log.debug('Deck "${deck.name}": all ${names.length} species resolved locally');
    }

    final currentIds = deck.speciesIds ?? {};
    deck.speciesIds = {...currentIds, ...resolved.values};
    return unresolved;
  }

  /// Resolves species names via iNaturalist synonym search.
  /// Returns a map of original name → local species ID for successfully resolved names.
  /// Used by the enrichment queue to resolve names that were not found locally during import.
  Future<Map<String, String>> resolveNamesViaInat(List<String> names) async {
    final iNatService = _iNatService;
    if (iNatService == null) return const {};
    final result = <String, String>{};

    for (final originalName in names) {
      final normalizedQuery = _normalizeToBinomial(originalName);
      if (normalizedQuery.isEmpty) continue;

      try {
        final taxa = await iNatService.searchTaxa(normalizedQuery);
        final candidateBinomials = taxa
            .map((row) => row['scientific_name'] as String?)
            .whereType<String>()
            .map(_normalizeToBinomial)
            .where((name) => name.isNotEmpty)
            .toList();
        if (candidateBinomials.isEmpty) continue;

        final resolvedCandidates = await _speciesRepository.resolveFullNames(
          candidateBinomials,
        );

        for (final candidate in candidateBinomials) {
          final speciesId = resolvedCandidates[candidate];
          if (speciesId != null) {
            result[originalName] = speciesId;
            _log.debug(
              'Resolved "$originalName" via iNat candidate "$candidate"',
            );
            break;
          }
        }
      } catch (error) {
        _log.warn('iNat name resolution failed for "$originalName": $error');
      }
    }

    return result;
  }

  String _normalizeToBinomial(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return '';
    return '${parts[0]} ${parts[1]}';
  }

  CreateDeck _cloneDeck(CreateDeck source) {
    final clone = CreateDeck(
      id: source.id,
      name: source.name,
      description: source.description,
      language: source.language,
      speciesNames: source.speciesNames == null
          ? null
          : Set<String>.from(source.speciesNames!),
      speciesIds: source.speciesIds == null
          ? null
          : Set<String>.from(source.speciesIds!),
      imageUrl: source.imageUrl,
    );
    clone.coverImagePath = source.coverImagePath;
    return clone;
  }
}
