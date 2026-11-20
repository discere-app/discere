import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/logger.dart';

/// The translations a deck's JSON may carry for its own texts, and the one
/// place that picks among them.
///
/// A deck names itself in `name` and `description`, a subdeck in `name`.
/// Next to them, an optional `translations` object holds the same fields per
/// language, keyed by [Language.name]:
///
/// ```json
/// "translations": {
///   "en": { "name": "Sharks and Rays", "description": "…" },
///   "fr": { "name": "Requins et raies" }
/// }
/// ```
///
/// Each field is picked on its own, from the first of: the app's language,
/// English, the field itself. A French name without a French description
/// thus comes with the English description, or with the untranslated one.
///
/// The language is the one the app is displayed in, not the deck's learning
/// language, which picks the species' common names on its cards: the deck's
/// name and description are text of the app like any around them. They are
/// resolved once, when the deck is read, so a deck imported in one language
/// keeps its name when the app's language changes later, as it keeps a name
/// the user gave it.
///
/// The untranslated fields stay plain strings, and `translations` is an
/// addition an older app skips: it shows the untranslated texts, which is
/// what the deck says without translations. So translations need no new
/// format version (see `DeckFormat`). A language this app does not carry is
/// skipped quietly: the catalog serves every app version and may translate
/// into a language before an app carries it. A translation that is not a
/// non-empty string is a broken deck and skipped with a warning, rather
/// than making the deck unreadable.
abstract final class DeckTranslations {
  static final _log = Logger.forType(DeckTranslations);

  static const _translationsKey = 'translations';
  static const _deckFields = ['name', 'description'];
  static const _subdeckFields = ['name'];

  /// The language a field falls back to before its untranslated text.
  static const _fallbackLanguage = Language.en;

  /// [json] with the deck's and its subdecks' texts in [language] where the
  /// deck translates them, and without `translations`. [json] itself is left
  /// as it is.
  static Map<String, dynamic> resolve(
    Map<String, dynamic> json,
    Language language,
  ) {
    final resolved = _resolveFields(json, _deckFields, language);
    final subdecks = json['subdecks'];
    if (subdecks is List) {
      resolved['subdecks'] = [
        for (final subdeck in subdecks)
          subdeck is Map<String, dynamic>
              ? _resolveFields(subdeck, _subdeckFields, language)
              : subdeck,
      ];
    }
    return resolved;
  }

  /// A copy of [json] with each of [fields] taken from the first language of
  /// the fallback chain that translates it, and without `translations`.
  static Map<String, dynamic> _resolveFields(
    Map<String, dynamic> json,
    List<String> fields,
    Language language,
  ) {
    final translations = _translationsIn(json);
    final resolved = Map<String, dynamic>.of(json)..remove(_translationsKey);
    for (final field in fields) {
      for (final candidate in {language, _fallbackLanguage}) {
        final text = _textIn(translations[candidate], field, candidate);
        if (text != null) {
          resolved[field] = text;
          break;
        }
      }
    }
    return resolved;
  }

  /// The translations [json] carries, per language this app carries.
  static Map<Language, Map<Object?, Object?>> _translationsIn(
    Map<String, dynamic> json,
  ) {
    final translations = json[_translationsKey];
    if (translations == null) return const {};
    if (translations is! Map) {
      _log.warn('Ignoring translations that are not an object');
      return const {};
    }
    final languages = Language.values.asNameMap();
    final byLanguage = <Language, Map<Object?, Object?>>{};
    for (final MapEntry(:key, :value) in translations.entries) {
      final language = languages[key];
      if (language == null) continue;
      if (value is! Map) {
        _log.warn('Ignoring $key translations that are not an object');
      } else {
        byLanguage[language] = value;
      }
    }
    return byLanguage;
  }

  /// [field] as [translation] gives it in [language], or `null` where it
  /// gives none that can stand in for the field.
  static String? _textIn(
    Map<Object?, Object?>? translation,
    String field,
    Language language,
  ) {
    final text = translation?[field];
    if (text == null) return null;
    if (text is String && text.trim().isNotEmpty) return text;
    _log.warn('Ignoring the ${language.name} $field "$text"');
    return null;
  }
}
