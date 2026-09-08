/// Combines the common names a taxon has from several sources into one list
/// per language.
///
/// There are three of them and they do not rank the same way. The reference
/// DB carries one curated name per language in fixed columns. The user DB's
/// `runtime_common_names` carries names fetched from iNaturalist, ordered by
/// how well they match the user's place. And a parent taxon can stand in for
/// a child that has no name of its own.
///
/// Kept apart from the queries that fetch them: none of these rules needs a
/// database to state or to check.
library;

import 'package:discere/shared/model/language.dart';

/// The languages the reference DB has `common_name_*` columns for.
const referenceLanguages = [
  Language.en,
  Language.de,
  Language.fr,
  Language.es,
];

/// A single reference-DB column value as a list — empty when the column is
/// null or blank, so every source can be treated the same way.
List<String> wrapName(String? raw) {
  final value = raw?.trim();
  return (value != null && value.isNotEmpty) ? [value] : const [];
}

/// The four `common_name_*` columns of [row], by language.
Map<Language, List<String>> localizedListMap(Map<String, Object?>? row) {
  if (row == null) return const {};
  return {
    for (final language in referenceLanguages)
      language: wrapName(row['common_name_${language.name}'] as String?),
  };
}

/// The first non-empty `<prefix>_common_name_*` column of [row].
///
/// Used where a joined ancestor contributes a name for a breadcrumb and any
/// language will do — the alternative would be showing nothing.
String? localizedName(Map<String, Object?> row, String prefix) {
  for (final language in referenceLanguages) {
    final value = row['${prefix}_common_name_${language.name}'] as String?;
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// [own] wins per language, wholesale — a language that has any name of its
/// own does not get [inherited] appended.
///
/// Used where the inherited names belong to a *different* taxon (a genus
/// standing in for a species), which makes them a substitute rather than
/// more names for the same thing.
Map<Language, List<String>> preferOwnNames(
  Map<Language, List<String>> own,
  Map<Language, List<String>> inherited,
) => {
  for (final language in Language.values)
    language: (own[language]?.isNotEmpty ?? false)
        ? own[language]!
        : (inherited[language] ?? const []),
};

/// Merges names for the *same* taxon: imported first, then the reference
/// name, duplicates dropped.
///
/// Imported names lead because they are place-aware — someone in Australia
/// should see the name used there ahead of the curated default.
Map<Language, List<String>> mergeLocalizedCommonNames(
  Map<Language, List<String>> referenceCommonNames,
  Map<Language, List<String>> importedCommonNames,
) => {
  for (final language in Language.values)
    language: mergeNameLists(
      importedCommonNames[language] ?? const [],
      referenceCommonNames[language] ?? const [],
    ),
};

/// [primary] first, then whatever in [secondary] is not already there.
///
/// Duplicates are judged case-insensitively with runs of whitespace
/// collapsed, because the sources spell the same name differently often
/// enough to matter. The spelling of the first occurrence is what survives.
List<String> mergeNameLists(List<String> primary, List<String> secondary) {
  if (secondary.isEmpty) return primary;
  if (primary.isEmpty) return secondary;

  final result = <String>[];
  final seen = <String>{};
  for (final name in [...primary, ...secondary]) {
    final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (normalized.isEmpty || seen.contains(normalized)) continue;
    seen.add(normalized);
    result.add(name);
  }
  return result;
}

/// The language for a `runtime_common_names.language_code`, or null for one
/// the app does not carry — those names are simply not shown.
Language? languageFromCode(String code) {
  for (final language in Language.values) {
    if (language.name == code) return language;
  }
  return null;
}
