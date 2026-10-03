import 'package:discere/shared/model/language.dart';

/// The languages a taxon's names can be switched to, given the one they
/// are [current]ly shown in.
///
/// A language without a common name for the taxon is left out rather than
/// offered disabled: picking it would only land on the English or
/// scientific-name fallback, which is reachable without it. The exception
/// is [current] itself, kept even without a name of its own — it is the
/// entry that carries the checkmark, and a menu that does not list what is
/// selected looks broken.
List<Language> selectableDisplayLanguages(
  Map<Language, List<String>> commonNames,
  Language current,
) => [
  for (final language in Language.values)
    if (language == current || (commonNames[language]?.isNotEmpty ?? false))
      language,
];
