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
