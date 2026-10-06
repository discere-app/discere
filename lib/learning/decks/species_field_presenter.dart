import 'package:discere/learning/decks/species_name_line.dart';

/// How the lines of the create-deck species field fare against the local
/// catalog, as the summary below the field shows it.
class SpeciesFieldCheck {
  /// Lines whose species the catalog knows.
  final int foundCount;

  /// Lines that can name a species but match nothing locally; after the deck
  /// is created, they are looked up on iNaturalist.
  final List<String> notFoundLocally;

  /// Lines that cannot name a species at all, so no lookup will ever match
  /// them; they are left out when the deck is created.
  final List<String> notSpeciesNames;

  const SpeciesFieldCheck({
    required this.foundCount,
    required this.notFoundLocally,
    required this.notSpeciesNames,
  });
}

/// Reads the create-deck species field: which lines it holds, which of them
/// are worth looking up, and what the lookup made of them.
class SpeciesFieldPresenter {
  const SpeciesFieldPresenter();

  /// The field's non-blank lines, trimmed and in order. A line repeating an
  /// earlier one is dropped — by genus and epithet for a species name, the
  /// way the catalog compares them, and by its whole text otherwise.
  List<String> lines(String text) {
    final lines = <String>[];
    final seenKeys = <String>{};
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final key = SpeciesNameLine.binomialKey(line) ?? line.toLowerCase();
      if (seenKeys.add(key)) lines.add(line);
    }
    return lines;
  }

  /// The [lines] a catalog lookup can match — the only ones it is given.
  List<String> speciesNames(List<String> lines) => [
    for (final line in lines)
      if (SpeciesNameLine.binomialKey(line) != null) line,
  ];

  /// Sorts [lines] by the lookup's answer, [resolvedByName] being what it
  /// returned for [speciesNames] of these lines.
  SpeciesFieldCheck check(
    List<String> lines,
    Map<String, String> resolvedByName,
  ) {
    var foundCount = 0;
    final notFoundLocally = <String>[];
    final notSpeciesNames = <String>[];
    for (final line in lines) {
      if (SpeciesNameLine.binomialKey(line) == null) {
        notSpeciesNames.add(line);
      } else if (resolvedByName.containsKey(line)) {
        foundCount++;
      } else {
        notFoundLocally.add(line);
      }
    }
    return SpeciesFieldCheck(
      foundCount: foundCount,
      notFoundLocally: notFoundLocally,
      notSpeciesNames: notSpeciesNames,
    );
  }

  /// The first [max] of [names] for display, and how many are left out.
  ({List<String> shown, int hiddenCount}) abbreviate(
    List<String> names, {
    int max = 3,
  }) {
    if (names.length <= max) return (shown: names, hiddenCount: 0);
    return (shown: names.sublist(0, max), hiddenCount: names.length - max);
  }
}
