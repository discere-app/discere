/// Turns a typed search term into text that is safe to bind to an FTS
/// `MATCH ?` in [SearchRepository].
///
/// It sits beside `search_sql.dart` rather than in `search_text.dart`: that
/// one is the normalisation rule the index and the search worker share,
/// while this one only concerns how a term is phrased as an FTS4 query.
library;

final _ftsSyntaxCharacters = RegExp(r'["()\-]');
final _whitespaceRun = RegExp(r'\s+');

/// Replaces `"`, `(`, `)` and `-` in [term] with spaces, collapses
/// whitespace and trims. An empty result means there is nothing left to
/// match.
///
/// The platforms do not agree on the FTS4 query syntax. Android's SQLite
/// parses the standard syntax: there `-` negates the token after it, even
/// in the middle of a word, so a hyphenated name stops matching itself, and
/// an unpaired `"` fails the whole expression (`malformed MATCH
/// expression`). Under the enhanced syntax an unpaired `(` or `)` fails it
/// as well. The rule has to hold under both. Dropping the hyphen loses
/// nothing: the unicode61 tokenizer splits names at it anyway, so
/// `arc en ciel*` finds what `arc-en-ciel` names, only without binding the
/// words into a phrase. The term is not quoted, because a prefix `*` does
/// not apply inside a quoted phrase.
///
/// Case is left alone, which leaves operator words (`AND`, `OR`, `NEAR`)
/// to whatever the platform's syntax makes of them; that is a separate
/// question from keeping the expression parseable.
///
/// The prefix `*` is not appended here: whether a term gets one is each
/// search path's own rule.
String ftsMatchTerm(String term) => term
    .replaceAll(_ftsSyntaxCharacters, ' ')
    .replaceAll(_whitespaceRun, ' ')
    .trim();
