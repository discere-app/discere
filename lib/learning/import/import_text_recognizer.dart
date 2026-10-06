import 'dart:convert';

import 'package:discere/learning/decks/species_name_line.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';

/// What [ImportTextRecognizer] made of a pasted, picked or scanned text.
sealed class RecognizedImport {
  const RecognizedImport();
}

/// A whole deck in one of the encodings the app itself exports.
sealed class RecognizedDeck extends RecognizedImport {
  final CreateDeck deck;

  const RecognizedDeck(this.deck);
}

/// The plain JSON the app shares as text or saves as a file.
final class RecognizedDeckJson extends RecognizedDeck {
  const RecognizedDeckJson(super.deck);
}

/// The gzip+base64 JSON the app puts into its share QR code.
final class RecognizedQrPayload extends RecognizedDeck {
  const RecognizedQrPayload(super.deck);
}

/// Scientific names, one per line — what the species-list export produces.
final class RecognizedSpeciesList extends RecognizedImport {
  /// Every cleaned line, in input order and without duplicates — including
  /// lines that cannot name a species. Those are not dropped here but shown
  /// as such in the species field the list is filled into, where the user
  /// can correct them.
  final Set<String> speciesNames;

  const RecognizedSpeciesList(this.speciesNames);
}

/// None of the formats above.
final class UnrecognizedImport extends RecognizedImport {
  const UnrecognizedImport();
}

/// Tells the import formats apart, so pasting, picking a file and scanning a
/// QR code all accept the same inputs without the user naming the format.
///
/// The formats are told apart by their first characters, before anything is
/// decoded: a JSON object starts with `{`, which is neither base64 nor part
/// of a taxon name, and a gzip payload starts with the base64 form of the
/// gzip signature (`H4s`), which no list opening with a species name does —
/// not even with its whitespace removed, since a genus has no digits. A text
/// whose head points to a deck encoding but does not decode as one is
/// unrecognized; it is never retried as a species list, since a deck payload
/// is never a list of names.
class ImportTextRecognizer {
  /// What base64 is made of, once whitespace is removed: a payload passed on
  /// as text often comes back wrapped by a mail or messenger client, and
  /// base64 carries no meaningful whitespace. A species list with its spaces
  /// removed may consist of base64 characters too; the gzip signature at the
  /// head is what rules it out.
  static final _base64 = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

  /// The two bytes every gzip stream starts with.
  static const _gzipMagic = [0x1f, 0x8b];

  static final _listMarker = RegExp(r'^(?:[-*•]|\d+[.)])\s*');
  static final _whitespaceRun = RegExp(r'\s+');

  final DeckSerializationWorker _serializationWorker;

  const ImportTextRecognizer(this._serializationWorker);

  Future<RecognizedImport> recognize(String text) async {
    final trimmed = text.trim();

    if (trimmed.startsWith('{')) {
      final deck = await _decodeDeck(
        () => _serializationWorker.decodeJson(trimmed),
      );
      return deck == null
          ? const UnrecognizedImport()
          : RecognizedDeckJson(deck);
    }

    final compact = trimmed.replaceAll(_whitespaceRun, '');
    if (_isGzipBase64(compact)) {
      final deck = await _decodeDeck(
        () => _serializationWorker.decodeGzipBase64(compact),
      );
      return deck == null
          ? const UnrecognizedImport()
          : RecognizedQrPayload(deck);
    }

    final speciesNames = _parseSpeciesList(trimmed);
    return speciesNames == null
        ? const UnrecognizedImport()
        : RecognizedSpeciesList(speciesNames);
  }

  /// Checks only the head of [text], which is enough to tell a gzip payload
  /// from a word that happens to consist of base64 characters; decoding the
  /// whole payload is left to the worker isolate.
  bool _isGzipBase64(String text) {
    if (text.length < 4 || !_base64.hasMatch(text)) return false;
    final head = base64Decode(text.substring(0, 4));
    return head.length >= 2 &&
        head[0] == _gzipMagic[0] &&
        head[1] == _gzipMagic[1];
  }

  /// The decoded deck, or null when the text has the shape of a deck
  /// encoding but does not hold one: malformed JSON or gzip, or a JSON
  /// object without the fields a deck needs.
  Future<CreateDeck?> _decodeDeck(
    Future<Map<String, dynamic>> Function() decode,
  ) async {
    try {
      return CreateDeck.fromJson(await decode());
    } on FormatException {
      return null;
    } on TypeError {
      // What the generated fromJson throws for a missing or mistyped field.
      return null;
    }
  }

  /// The lines of [text], or null when it is not a species list.
  ///
  /// Tolerates what hand-written and copied lists carry around the names —
  /// blank lines, `#` comments, list markers, uneven spacing — but does not
  /// rewrite the lines themselves, and keeps those that cannot name a
  /// species: judging a list is the species field's job, where the user sees
  /// the verdict and can fix a line. One line that can name a species
  /// (see [SpeciesNameLine]) is enough to make the text a list; without any,
  /// it is prose or a broken paste. Duplicates are told apart the way the
  /// catalog lookup does, by genus and epithet regardless of case.
  Set<String>? _parseSpeciesList(String text) {
    final lines = <String>{};
    final seenKeys = <String>{};
    var hasSpeciesName = false;
    for (final rawLine in const LineSplitter().convert(text)) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final line = trimmed
          .replaceFirst(_listMarker, '')
          .replaceAll(_whitespaceRun, ' ')
          .trim();
      if (line.isEmpty) continue;
      final binomialKey = SpeciesNameLine.binomialKey(line);
      hasSpeciesName = hasSpeciesName || binomialKey != null;
      if (seenKeys.add(binomialKey ?? line.toLowerCase())) lines.add(line);
    }
    return hasSpeciesName ? lines : null;
  }
}
