/// A named collection of species the user looks at side by side, to tell
/// similar ones apart.
class ComparisonList {
  final String id;
  final String name;

  /// In the order they were added, each at most once.
  final List<String> speciesIds;

  const ComparisonList({
    required this.id,
    required this.name,
    required this.speciesIds,
  });
}
