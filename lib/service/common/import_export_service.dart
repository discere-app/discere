import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:ui';


import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../model/language.dart';
import '../../model/ui/create_deck.dart';
import '../../persistence/species_repository.dart';
import '../../util/json_export_util.dart';
import '../learning/decks_service.dart';
import 'image_service.dart';

class ImportExportService {
  final DecksService _decksService;
  final SpeciesRepository _speciesRepository;
  final ImageService _imageService;

  ImportExportService(this._decksService, this._speciesRepository, this._imageService);

  // ─── Export Logic ──────────────────────────────────────────────────────────

  Future<String> exportDeckToJson(String deckId) async {
    final fullDeck = await _decksService.getCreateDeck(deckId);
    return jsonEncode(fullDeck.toJson());
  }

  Future<String> exportDeckToGzip(String deckId) async {
    final fullDeck = await _decksService.getCreateDeck(deckId);
    return JsonExportUtil.encode(fullDeck);
  }

  Future<bool> saveJsonToFile({
    required String jsonData,
    required String deckName,
    required String exportPrefix,
  }) async {
    final fileName = '${exportPrefix}_${deckName.replaceAll(' ', '_')}.json';

    try {
      // 1. Request Permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }

      // 2. Determine Path
      String path = await _getExportPath(fileName);

      // 3. Write File
      final file = File(path);
      await file.writeAsString(jsonData);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error saving JSON to file: $e');
      }
      return false;
    }
  }

  Future<void> shareDeckAsFile({
    required String jsonData,
    required String deckName,
    required String exportPrefix,
    String? subject,
  }) async {
    final fileName = '${exportPrefix}_${deckName.replaceAll(' ', '_')}.json';
    final directory = await getTemporaryDirectory();
    final tempPath = '${directory.path}/$fileName';
    final file = File(tempPath);
    await file.writeAsString(jsonData);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(tempPath, mimeType: 'application/json')],
      subject: subject ?? fileName,
    ));
  }

  Future<void> shareDeckAsSpeciesListText({
    required String deckId,
    required String deckName,
    Rect? sharePositionOrigin,
  }) async {
    final speciesList = await _decksService.getSpeciesByDeckId(deckId);

    // Export raw binomial names only, one per line, for easier importing
    final shareText = speciesList.map((s) => s.getBinomialName()).join('\n');

    await SharePlus.instance.share(ShareParams(
      text: shareText,
      subject: deckName,
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  Future<void> shareDeckAsJsonText({
    required String deckId,
    required String deckName,
    Rect? sharePositionOrigin,
  }) async {
    final fullDeck = await _decksService.getCreateDeck(deckId);
    final jsonData = jsonEncode(fullDeck.toJson());

    await SharePlus.instance.share(ShareParams(
      text: jsonData,
      subject: deckName,
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  // ─── Import Logic ──────────────────────────────────────────────────────────

  Future<void> importDeckFromJson(String jsonText) async {
    final deck = CreateDeck.fromJsonString(jsonText);
    return _finalizeImport(deck);
  }

  Future<void> importDeckFromGzip(String gzipEncodedText) async {
    if (gzipEncodedText.trim().isEmpty) return;

    try {
      return JsonExportUtil.decode<Future<void>>(gzipEncodedText, (map) async {
        final deck = CreateDeck.fromJson(map);
        return _finalizeImport(deck);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error decoding GZIP deck: $e');
      }
      rethrow;
    }
  }

  Future<void> importDeckFromSpeciesNames({
    required String name,
    required String description,
    required List<String> scientificNames,
    Language? language,
    String? coverImagePath,
  }) async {
    if (scientificNames.isEmpty) {
      var deck = CreateDeck(
          name: name,
          description: description,
          language: language,
          speciesIds: {})
        ..coverImagePath = coverImagePath;
      await _decksService.createDeck(deck);
      return;
    }

    final speciesIds =
        await _speciesRepository.getSpeciesIdsByFullNames(scientificNames);

    var deck = CreateDeck(
        name: name,
        description: description,
        language: language,
        speciesIds: speciesIds)
      ..coverImagePath = coverImagePath;
    await _decksService.createDeck(deck);
  }

  // ─── Internal Helpers ──────────────────────────────────────────────────────

  Future<void> _finalizeImport(CreateDeck deck) async {
    if (deck.imageUrl != null && deck.coverImagePath == null) {
      try {
        final localPath = await _imageService.downloadAndSaveDeckCover(deck.imageUrl!);
        deck.coverImagePath = localPath;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error downloading deck cover image: $e');
        }
      }
    }

    await _resolveSpeciesIds(deck);
    return _decksService.createDeck(deck);
  }

  Future<void> _resolveSpeciesIds(CreateDeck deck) async {
    final names = deck.speciesNames?.toList() ?? [];
    if (names.isEmpty) return;

    final resolvedIds =
        await _speciesRepository.getSpeciesIdsByFullNames(names);

    if (resolvedIds.isNotEmpty) {
      final currentIds = deck.speciesIds ?? {};
      deck.speciesIds = {...currentIds, ...resolvedIds};
    }
  }

  Future<String> _getExportPath(String fileName) async {
    if (Platform.isAndroid) {
      const downloadPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadPath);
      if (await dir.exists()) {
        return '$downloadPath/$fileName';
      }
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/$fileName';
    }
    
    final dir = await getTemporaryDirectory();
    return '${dir.path}/$fileName';
  }
}
