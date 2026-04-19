import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/enrichment/service/inat_name_resolution_service.dart';
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
  final INatNameResolutionService? _iNatNameResolutionService;

  DeckImportService(
    this._decksService,
    this._speciesRepository, {
    INaturalistService? iNatService,
  }) : _iNatNameResolutionService = iNatService == null
           ? null
           : INatNameResolutionService(_speciesRepository, iNatService);

  Future<DeckImportResult> importJson(String jsonText) async {
    // final totalStopwatch = Stopwatch()..start();
    try {
      // final parseStopwatch = Stopwatch()..start();
      final deck = CreateDeck.fromJsonString(jsonText);
      // parseStopwatch.stop();

      // final resolveStopwatch = Stopwatch()..start();
      final unresolved = await _resolveSpeciesIds(deck);
      // resolveStopwatch.stop();

      // final createStopwatch = Stopwatch()..start();
      final deckId = await _decksService.createDeck(deck);
      // createStopwatch.stop();
      // totalStopwatch.stop();
      // _log.debug(
      //   'Import JSON deck="${deck.name}" '
      //   'parse=${parseStopwatch.elapsedMilliseconds}ms '
      //   'resolve=${resolveStopwatch.elapsedMilliseconds}ms '
      //   'create=${createStopwatch.elapsedMilliseconds}ms '
      //   'total=${totalStopwatch.elapsedMilliseconds}ms '
      //   'resolved=${deck.speciesIds?.length ?? 0} '
      //   'unresolved=${unresolved.length}',
      // );
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
      // totalStopwatch.stop();
      // _log.warn(
      //   'Import JSON failed after ${totalStopwatch.elapsedMilliseconds}ms: $error',
      // );
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

    // final totalStopwatch = Stopwatch()..start();
    try {
      final deckId = await JsonExportUtil.decode<Future<String>>(gzipEncodedText, (
        map,
      ) async {
        // final parseStopwatch = Stopwatch()..start();
        final deck = CreateDeck.fromJson(map);
        // parseStopwatch.stop();
        // final resolveStopwatch = Stopwatch()..start();
        await _resolveSpeciesIds(deck);
        // resolveStopwatch.stop();
        // final createStopwatch = Stopwatch()..start();
        final createdDeckId = await _decksService.createDeck(deck);
        // createStopwatch.stop();
        // _log.debug(
        //   'Import GZIP deck="${deck.name}" '
        //   'parse=${parseStopwatch.elapsedMilliseconds}ms '
        //   'resolve=${resolveStopwatch.elapsedMilliseconds}ms '
        //   'create=${createStopwatch.elapsedMilliseconds}ms '
        //   'resolved=${deck.speciesIds?.length ?? 0}',
        // );
        return createdDeckId;
      });
      // totalStopwatch.stop();
      // _log.debug(
      //   'Import GZIP total=${totalStopwatch.elapsedMilliseconds}ms deckId=$deckId',
      // );
      return deckId;
    } catch (error) {
      // totalStopwatch.stop();
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

    // final totalStopwatch = Stopwatch()..start();
    final importedDeckIds = <String>[];
    final imageUrlByDeckId = <String, String>{};
    final unresolvedNamesByDeckId = <String, List<String>>{};
    String? lastError;

    await DecksService.runWithNotificationsSuppressed(() async {
      for (final deck in decks) {
        // final deckStopwatch = Stopwatch()..start();
        try {
          final importDeck = _cloneDeck(deck);
          // final resolveStopwatch = Stopwatch()..start();
          final unresolved = await _resolveSpeciesIds(importDeck);
          // resolveStopwatch.stop();
          // final createStopwatch = Stopwatch()..start();
          final deckId = await _decksService.createDeck(importDeck);
          // createStopwatch.stop();
          // deckStopwatch.stop();
          importedDeckIds.add(deckId);
          if (unresolved.isNotEmpty) {
            unresolvedNamesByDeckId[deckId] = unresolved;
          }
          if (importDeck.imageUrl != null &&
              importDeck.imageUrl!.trim().isNotEmpty) {
            imageUrlByDeckId[deckId] = importDeck.imageUrl!.trim();
          }
          // _log.debug(
          //   'Import deck="${importDeck.name}" '
          //   'resolve=${resolveStopwatch.elapsedMilliseconds}ms '
          //   'create=${createStopwatch.elapsedMilliseconds}ms '
          //   'total=${deckStopwatch.elapsedMilliseconds}ms '
          //   'resolved=${importDeck.speciesIds?.length ?? 0} '
          //   'unresolved=${unresolved.length}',
          // );
        } catch (error) {
          // deckStopwatch.stop();
          // _log.warn(
          //   'Import deck="${deck.name}" failed after '
          //   '${deckStopwatch.elapsedMilliseconds}ms: $error',
          // );
          lastError = error.toString();
        }
      }
    });

    if (importedDeckIds.isNotEmpty) {
      _decksService.notifyDecksChanged();
    }

    // totalStopwatch.stop();
    // _log.debug(
    //   'Import decks batch attempted=${decks.length} '
    //   'imported=${importedDeckIds.length} '
    //   'total=${totalStopwatch.elapsedMilliseconds}ms',
    // );
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

    // final resolveStopwatch = Stopwatch()..start();
    final resolved = <String, String>{
      ...await _speciesRepository.resolveFullNames(names),
    };
    // resolveStopwatch.stop();

    if (resolved.isEmpty) {
      _log.warn(
        'Deck "${deck.name}": none of ${names.length} species names could be resolved locally',
      );
      // _log.debug(
      //   'Deck "${deck.name}": local species lookup took '
      //   '${resolveStopwatch.elapsedMilliseconds}ms for ${names.length} names',
      // );
      return names;
    }

    final unresolved = names.where((n) => !resolved.containsKey(n)).toList();
    if (unresolved.isNotEmpty) {
      _log.debug(
        'Deck "${deck.name}": ${unresolved.length}/${names.length} species not found locally '
        '– will be resolved in background: ${unresolved.join(", ")}',
      );
    } else {
      _log.debug(
        'Deck "${deck.name}": all ${names.length} species resolved locally',
      );
    }
    // _log.debug(
    //   'Deck "${deck.name}": local species lookup took '
    //   '${resolveStopwatch.elapsedMilliseconds}ms for ${names.length} names',
    // );

    final currentIds = deck.speciesIds ?? {};
    deck.speciesIds = {...currentIds, ...resolved.values};
    return unresolved;
  }

  /// Resolves species names via iNaturalist synonym search.
  /// Returns a map of original name → local species ID for successfully resolved names.
  /// Used by the enrichment queue to resolve names that were not found locally during import.
  Future<Map<String, String>> resolveNamesViaInat(List<String> names) async {
    final service = _iNatNameResolutionService;
    if (service == null) return const {};
    return service.resolveNames(names);
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
