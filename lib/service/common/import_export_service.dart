import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../util/json_export_util.dart';
import '../learning/decks_service.dart';

class ImportExportService {
  final DecksService _decksService;

  ImportExportService(this._decksService);

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

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tempPath, mimeType: 'application/json')],
        subject: subject ?? fileName,
      ),
    );
  }

  Future<void> shareDeckAsSpeciesListText({
    required String deckId,
    required String deckName,
    Rect? sharePositionOrigin,
  }) async {
    final speciesList = await _decksService.getSpeciesByDeckId(deckId);

    // Export raw binomial names only, one per line, for easier importing
    final shareText = speciesList.map((s) => s.getBinomialName()).join('\n');

    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: deckName,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<void> shareDeckAsJsonText({
    required String deckId,
    required String deckName,
    Rect? sharePositionOrigin,
  }) async {
    final fullDeck = await _decksService.getCreateDeck(deckId);
    final jsonData = jsonEncode(fullDeck.toJson());

    await SharePlus.instance.share(
      ShareParams(
        text: jsonData,
        subject: deckName,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
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
