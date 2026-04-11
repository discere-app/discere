/// Splits a semicolon-separated string of common names into a deduplicated list.
///
/// Returns an empty list for null or blank input.
/// Preserves original casing while deduplicating case-insensitively.
/// Normalizes internal whitespace during comparison.
List<String> splitCommonNames(String? rawNames) {
  if (rawNames == null || rawNames.trim().isEmpty) return const [];

  final orderedNames = <String>[];
  final seenNames = <String>{};

  for (final rawName in rawNames.split(';')) {
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
