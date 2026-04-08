import 'package:flutter/foundation.dart';

import '../../model/language.dart';
import '../../model/ui/create_deck.dart';
import '../../persistence/species_repository.dart';
import '../../util/json_export_util.dart';
import '../learning/decks_service.dart';
import 'image_service.dart';

class DeckImportResult {
  final List<String> importedDeckIds;
  final String? lastError;
  final int attemptedCount;

  const DeckImportResult({
    required this.importedDeckIds,
    required this.lastError,
    required this.attemptedCount,
  });

  int get successCount => importedDeckIds.length;
  bool get hasSuccess => importedDeckIds.isNotEmpty;
  bool get allSucceeded => successCount == attemptedCount;
}

class DeckImportService {
  final DecksService _decksService;
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;

  DeckImportService(
    this._decksService,
    this._speciesRepository,
    this._imageService,
  );

  Future<DeckImportResult> importJson(String jsonText) async {
    try {
      final deck = CreateDeck.fromJsonString(jsonText);
      final deckId = await _finalizeImport(deck);
      return DeckImportResult(
        importedDeckIds: [deckId],
        lastError: null,
        attemptedCount: 1,
      );
    } catch (error) {
      return DeckImportResult(
        importedDeckIds: const [],
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
        return _finalizeImport(deck);
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error decoding GZIP deck: $error');
      }
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
        lastError: null,
        attemptedCount: 0,
      );
    }

    final importedDeckIds = <String>[];
    String? lastError;

    for (final deck in decks) {
      try {
        final deckId = await _finalizeImport(
          CreateDeck.fromJson(deck.toJson()),
        );
        importedDeckIds.add(deckId);
      } catch (error) {
        lastError = error.toString();
      }
    }

    return DeckImportResult(
      importedDeckIds: importedDeckIds,
      lastError: lastError,
      attemptedCount: decks.length,
    );
  }

  Future<String> _finalizeImport(CreateDeck deck) async {
    if (deck.imageUrl != null && deck.coverImagePath == null) {
      try {
        final localPath = await _imageService.downloadAndSaveDeckCover(
          deck.imageUrl!,
        );
        deck.coverImagePath = localPath;
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Error downloading deck cover image: $error');
        }
      }
    }

    await _resolveSpeciesIds(deck);
    return _decksService.createDeck(deck);
  }

  Future<void> _resolveSpeciesIds(CreateDeck deck) async {
    final names = deck.speciesNames?.toList() ?? [];
    if (names.isEmpty) return;

    final resolvedIds = await _speciesRepository.getSpeciesIdsByFullNames(
      names,
    );
    if (resolvedIds.isEmpty) return;

    final currentIds = deck.speciesIds ?? {};
    deck.speciesIds = {...currentIds, ...resolvedIds};
  }
}
