/// Whether a line of text can name a species, read the way the catalog
/// lookup reads it.
///
/// The lookup only ever matches a line's first two words, lower-cased, as
/// genus and epithet; whatever follows — an author and year, a variety — is
/// ignored. So a line names a species exactly when those two words can be a
/// genus and an epithet: letters of any script, hyphens and the hybrid sign.
/// A single word, or a line opening with a quote, bracket or digit, can never
/// match. Shared by the species field of the create-deck page and the
/// species-list import, so both agree on what counts as a name.
abstract final class SpeciesNameLine {
  static final _binomialHead = RegExp(
    r'^\s*([\p{L}×][\p{L}\-×]*)\s+([\p{L}×][\p{L}\-×]*)(?:\s|$)',
    unicode: true,
  );

  /// Genus and epithet of [line] in lower case, single-spaced — the key the
  /// catalog looks names up by — or null when [line] cannot name a species.
  static String? binomialKey(String line) {
    final match = _binomialHead.firstMatch(line);
    if (match == null) return null;
    return '${match[1]} ${match[2]}'.toLowerCase();
  }
}
