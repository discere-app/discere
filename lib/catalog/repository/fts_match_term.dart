/// Turns a typed search term into text that is safe to bind to an FTS
/// `MATCH ?` in [SearchRepository].
///
/// It sits beside `search_sql.dart` rather than in `search_text.dart`: that
/// one is the normalisation rule the index and the search worker share,
/// while this one only concerns how a term is phrased as an FTS4 query.
library;

final _ftsSyntaxBreakingCharacters = RegExp(r'["()]');
final _whitespaceRun = RegExp(r'\s+');

/// Replaces `"`, `(` and `)` in [term] with spaces, collapses whitespace and
/// trims. An empty result means there is nothing left to match.
///
/// These are the only characters that, left unpaired, make FTS4 reject the
/// whole expression (`malformed MATCH expression`); hyphens, apostrophes,
/// `:`, `^` and `-` parse and are left alone. The term is not quoted,
/// because a prefix `*` does not apply inside a quoted phrase, and its case
/// is kept, because lowercasing would turn an `AND`/`OR`/`NEAR` operator
/// into a search word.
///
/// The prefix `*` is not appended here: whether a term gets one is each
/// search path's own rule.
String ftsMatchTerm(String term) => term
    .replaceAll(_ftsSyntaxBreakingCharacters, ' ')
    .replaceAll(_whitespaceRun, ' ')
    .trim();
