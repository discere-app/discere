/// The format a deck's JSON declares, as [DeckFormat.declaredIn] reads it.
sealed class DeclaredDeckFormat {
  const DeclaredDeckFormat();
}

/// A format this app reads, so the deck can be read with `CreateDeck.fromJson`.
final class ReadableDeckFormat extends DeclaredDeckFormat {
  final int version;

  const ReadableDeckFormat(this.version);
}

/// A format only a newer app reads. Reading the deck anyway would drop what
/// that format adds and give a deck its author did not make.
final class NewerDeckFormat extends DeclaredDeckFormat {
  final int version;

  const NewerDeckFormat(this.version);
}

/// A version that is not a positive whole number: a broken deck, not one of
/// a newer format.
final class MalformedDeckFormat extends DeclaredDeckFormat {
  const MalformedDeckFormat();
}

/// The versions of the deck JSON — the online catalog and a deck shared as
/// text, file or QR code alike — and the one place that knows them.
///
/// A deck declares its version in `formatVersion`, a whole number; a deck
/// without one is version 1. The version goes up only for a change an app
/// that ignores it would read wrongly or lossily — version 2 brought
/// `subdecks` and `supersedes`. A field an older app can safely skip, such
/// as the learning settings, is optional within the current version, and
/// what its absence means is part of the format and never changes.
///
/// An app reads every version up to [supportedVersion] — older decks are
/// never migrated in place, since nobody holds all the shared copies, but
/// mapped onto the current model while reading — and turns down a newer one
/// rather than import part of it. The version is always the declared one:
/// an app cannot recognise the features of a format it does not know.
///
/// A deck is written in the lowest version that holds it ([requiredVersion]),
/// so an app that reads only older versions still reads every deck that
/// needs nothing newer. The catalog keeps one index per version, each
/// listing the decks up to that version, and the app reads the index of
/// [supportedVersion].
abstract final class DeckFormat {
  /// The newest version this app reads.
  static const supportedVersion = 2;

  static const _versionKey = 'formatVersion';

  /// What a deck without [_versionKey] is.
  static const _defaultVersion = 1;

  /// The version [json] declares, judged against [supportedVersion]. Only a
  /// JSON integer counts as a version: `"2"` or `2.0` make a broken deck.
  static DeclaredDeckFormat declaredIn(Map<String, dynamic> json) {
    final version = json[_versionKey] ?? _defaultVersion;
    if (version is! int || version < _defaultVersion) {
      return const MalformedDeckFormat();
    }
    return version > supportedVersion
        ? NewerDeckFormat(version)
        : ReadableDeckFormat(version);
  }

  /// The lowest version that holds the deck [json] is written as: 2 for a
  /// deck with subdecks — an older app would import it without them — and 1
  /// otherwise. Unlike reading, writing may judge by content, since the app
  /// writes only what it knows. `supersedes` does not count, as it is never
  /// written.
  static int requiredVersion(Map<String, dynamic> json) {
    final subdecks = json['subdecks'];
    return subdecks is List && subdecks.isNotEmpty ? 2 : _defaultVersion;
  }

  /// [json] with the field declaring its [requiredVersion] in front; without
  /// one for version 1, which a missing field stands for, so a QR code
  /// carries no byte more than it needs.
  static Map<String, dynamic> declare(Map<String, dynamic> json) {
    final version = requiredVersion(json);
    return {if (version != _defaultVersion) _versionKey: version, ...json};
  }
}
