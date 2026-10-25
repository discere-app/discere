/// [name] reduced to the lower-cased genus and epithet the reference
/// database matches scientific names by (`normalized_name`), or an empty
/// string when it does not have two words.
String normalizeToBinomial(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length < 2) return '';
  return '${parts[0].toLowerCase()} ${parts[1].toLowerCase()}';
}

/// A [normalizeToBinomial] result as a name to show: the genus capitalized
/// again ("carcharodon carcharias" → "Carcharodon carcharias").
String displayBinomial(String normalizedBinomial) {
  final parts = normalizedBinomial.split(' ');
  if (parts.length < 2) return normalizedBinomial;
  final genus = parts.first;
  final epithet = parts[1];
  return '${genus[0].toUpperCase()}${genus.substring(1)} $epithet';
}
