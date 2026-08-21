import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_name_resolution_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_update_diff.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/logger.dart';

class DeckImportResult {
  final List<String> importedDeckIds;
  final Map<String, String> imageUrlByDeckId;

  /// Species names that could not be resolved locally, grouped by deck ID.
  /// These will be resolved in the background via iNaturalist.
  final Map<String, List<String>> unresolvedNamesByDeckId;

  /// The exception from the last failed deck in the batch (or null on full
  /// success). Kept as the raw error rather than a pre-stringified message so
  /// the UI can localize it by type via `AppExceptionLocalization`.
  final Object? lastError;
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
  final DeckSerializationWorker _serializationWorker;

  DeckImportService(
    this._decksService,
    this._speciesRepository, {
    INaturalistService? iNatService,
    DeckSerializationWorker? serializationWorker,
  }) : _iNatNameResolutionService = iNatService == null
           ? null
           : INatNameResolutionService(_speciesRepository, iNatService),
       _serializationWorker =
           serializationWorker ?? const DeckSerializationWorker();

  Future<DeckImportResult> importJson(String jsonText) async {
    // final totalStopwatch = Stopwatch()..start();
    try {
      // final parseStopwatch = Stopwatch()..start();
      final deck = CreateDeck.fromJson(
        await _serializationWorker.decodeJson(jsonText),
      );
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
      _log.warn('Import JSON failed: $error');
      return DeckImportResult(
        importedDeckIds: const [],
        imageUrlByDeckId: const {},
        lastError: error,
        attemptedCount: 1,
      );
    }
  }

  /// Decodes [jsonText] into a [CreateDeck] without persisting it, so the
  /// caller can review/edit the values (e.g. via [CreateDeckPage]) before
  /// deciding to create the deck.
  Future<CreateDeck> parseJson(String jsonText) async {
    return CreateDeck.fromJson(await _serializationWorker.decodeJson(jsonText));
  }

  /// Decodes a QR-scanned/gzip-base64 payload into a [CreateDeck] without
  /// persisting it — the QR counterpart to [parseJson].
  Future<CreateDeck> parseGzip(String gzipEncodedText) async {
    if (gzipEncodedText.trim().isEmpty) {
      throw FormatException('Empty GZIP input');
    }
    return CreateDeck.fromJson(
      await _serializationWorker.decodeGzipBase64(gzipEncodedText),
    );
  }

  Future<String> importGzip(String gzipEncodedText) async {
    if (gzipEncodedText.trim().isEmpty) {
      throw FormatException('Empty GZIP input');
    }

    // final totalStopwatch = Stopwatch()..start();
    try {
      final deck = CreateDeck.fromJson(
        await _serializationWorker.decodeGzipBase64(gzipEncodedText),
      );
      await _resolveSpeciesIds(deck);
      final deckId = await _decksService.createDeck(deck);
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
    Object? lastError;

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
          lastError = error;
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

  /// Compares [deckId]'s current species against [remote]'s catalog entry,
  /// so the deck-update dialog can show the user what a refresh would add or
  /// remove before applying anything.
  Future<DeckUpdateDiff> diffForUpdate(String deckId, CreateDeck remote) async {
    final currentSpecies = await _decksService.getSpeciesByDeckId(deckId);
    final currentIds = currentSpecies.map((s) => s.id).toSet();
    final currentById = {for (final s in currentSpecies) s.id: s};

    final remoteNames = remote.speciesNames?.toList() ?? const [];
    final resolved = await _speciesRepository.resolveFullNames(remoteNames);
    final remoteIds = resolved.values.toSet();

    final addedIds = remoteIds.difference(currentIds);
    final removedIds = currentIds.difference(remoteIds);

    final addedSpecies = addedIds.isEmpty
        ? const <Species>[]
        : await _decksService.getSpeciesByIds(addedIds);
    final removedSpecies = [
      for (final id in removedIds)
        if (currentById[id] != null) currentById[id]!,
    ];
    final unresolvedAddedNames = remoteNames
        .where((name) => !resolved.containsKey(name))
        .toList();

    return DeckUpdateDiff(
      addedSpecies: addedSpecies,
      removedSpecies: removedSpecies,
      unresolvedAddedNames: unresolvedAddedNames,
    );
  }

  /// Applies a previously computed [diff] to [deckId]: name/description/
  /// cover/language are left untouched (a deck update only ever touches
  /// species membership), while `sourceId`/`updatedAt` are always bumped to
  /// [remote]'s values so the deck stops showing as outdated even if the
  /// user declines both the additions and the removals. Returns the names
  /// from [diff.unresolvedAddedNames] that still need background iNaturalist
  /// resolution — empty unless [includeAdditions] is true.
  Future<List<String>> applyDeckUpdate({
    required String deckId,
    required CreateDeck remote,
    required DeckUpdateDiff diff,
    required bool includeAdditions,
    required bool includeRemovals,
  }) async {
    final current = await _decksService.getCreateDeck(deckId);
    final newSpeciesIds = {...?current.speciesIds};
    if (includeAdditions) {
      newSpeciesIds.addAll(diff.addedSpecies.map((s) => s.id));
    }
    if (includeRemovals) {
      newSpeciesIds.removeAll(diff.removedSpecies.map((s) => s.id));
    }

    final updatedDeck = BaseDeck(
      deckId,
      current.name,
      current.description,
      coverImagePath: current.coverImagePath,
      language: current.language,
      sourceId: remote.sourceId,
      updatedAt: remote.updatedAt,
    );
    await _decksService.updateDeck(updatedDeck, newSpeciesIds);

    return includeAdditions ? diff.unresolvedAddedNames : const [];
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
      sourceId: source.sourceId,
      updatedAt: source.updatedAt,
    );
    clone.coverImagePath = source.coverImagePath;
    return clone;
  }
}
