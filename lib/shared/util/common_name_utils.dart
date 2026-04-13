import 'package:discere/shared/model/language.dart';

/// Splits a semicolon-separated string of common names into a deduplicated list.
///
/// Returns an empty list for null or blank input.
/// Preserves original casing while deduplicating case-insensitively.
/// Normalizes internal whitespace during comparison.
List<String> splitCommonNames(String? rawNames) {
  if (rawNames == null || rawNames.trim().isEmpty) return const [];

  return deduplicateCommonNames(rawNames.split(';'));
}

/// Deduplicates and trims common names while preserving order and casing.
List<String> deduplicateCommonNames(Iterable<String> rawNames) {
  final orderedNames = <String>[];
  final seenNames = <String>{};

  for (final rawName in rawNames) {
    final trimmedName = rawName.trim();
    if (trimmedName.isEmpty) continue;

    final normalizedName = trimmedName
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalizedName.isEmpty || seenNames.contains(normalizedName)) continue;

    seenNames.add(normalizedName);
    orderedNames.add(trimmedName);
  }

  return orderedNames;
}

/// Resolves common names for the given [language] with English fallback.
///
/// Looks up the preferred language first; if that yields no names,
/// falls back to English (unless already English).
List<String> resolveCommonNames(
  Map<Language, List<String>> commonNames,
  Language language,
) {
  final localized = commonNames[language];
  if (localized != null && localized.isNotEmpty) {
    return deduplicateCommonNames(localized);
  }

  if (language != Language.en) {
    final english = commonNames[Language.en];
    if (english != null && english.isNotEmpty) {
      return deduplicateCommonNames(english);
    }
  }

  return const [];
}

/// Returns the primary (first) common name, or [fallback] if none available.
String resolvePrimaryCommonName(
  Map<Language, List<String>> commonNames,
  Language language, {
  required String fallback,
}) {
  final resolved = resolveCommonNames(commonNames, language);
  return resolved.isNotEmpty ? resolved.first : fallback;
}

/// Returns all resolved names except the primary name.
List<String> resolveAdditionalCommonNames(
  Map<Language, List<String>> commonNames,
  Language language,
) {
  final resolved = resolveCommonNames(commonNames, language);
  return resolved.length <= 1 ? const [] : resolved.skip(1).toList();
}
