import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shows the platform's own save dialog and writes [bytes] wherever the user
/// picks; resolves to `null` when the user dismisses the dialog.
typedef SystemFileSaver =
    Future<Uri?> Function({
      required String fileName,
      required Uint8List bytes,
      required String mimeType,
    });

/// How [DeckExportService.saveJsonToFile] ended.
enum DeckFileSaveResult { saved, cancelled, failed }

/// Turns a deck into something shareable: JSON, a gzipped blob, a file, or
/// a plain species list.
///
/// Export only, despite what the folder around it does otherwise — reading a
/// deck back in is [DeckImportService]'s job, and the two share neither a
/// format concern nor a caller.
class DeckExportService {
  static final _log = Logger.forType(DeckExportService);
  final DecksService _decksService;
  final DeckSerializationWorker _serializationWorker;
  final SystemFileSaver _fileSaver;

  DeckExportService(
    this._decksService, {
    required SystemFileSaver fileSaver,
    DeckSerializationWorker? serializationWorker,
  }) : _fileSaver = fileSaver,
       _serializationWorker =
           serializationWorker ?? const DeckSerializationWorker();

  // ─── Export Logic ──────────────────────────────────────────────────────────

  Future<String> exportDeckToJson(String deckId) async {
    final fullDeck = await _decksService.getCreateDeck(deckId);
    return _serializationWorker.encodeJson(fullDeck.toJson());
  }

  Future<String> exportDeckToGzip(String deckId) async {
    final fullDeck = await _decksService.getCreateDeck(deckId);
    return _serializationWorker.encodeGzipBase64(fullDeck.toJson());
  }

  /// Saves through the system save dialog rather than to a fixed path: the
  /// dialog writes the file itself, so neither platform asks for a storage
  /// permission, and the user decides where the deck ends up.
  Future<DeckFileSaveResult> saveJsonToFile({
    required String jsonData,
    required String deckName,
    required String exportPrefix,
  }) async {
    try {
      final savedUri = await _fileSaver(
        fileName: _exportFileName(deckName, exportPrefix),
        bytes: utf8.encode(jsonData),
        mimeType: 'application/json',
      );
      return savedUri == null
          ? DeckFileSaveResult.cancelled
          : DeckFileSaveResult.saved;
    } catch (e) {
      _log.warn('Error saving JSON to file: $e');
      return DeckFileSaveResult.failed;
    }
  }

  Future<void> shareDeckAsFile({
    required String jsonData,
    required String deckName,
    required String exportPrefix,
    String? subject,
  }) async {
    final fileName = _exportFileName(deckName, exportPrefix);
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
    final jsonData = await exportDeckToJson(deckId);

    await SharePlus.instance.share(
      ShareParams(
        text: jsonData,
        subject: deckName,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  String _exportFileName(String deckName, String exportPrefix) =>
      '${exportPrefix}_${deckName.replaceAll(' ', '_')}.json';
}
