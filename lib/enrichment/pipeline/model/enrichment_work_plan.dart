class TaxonomyWorkPlanItem {
  final String workKey;
  final String runtimeEntityKey;
  final String rank;
  final String scientificName;
  final Set<String> speciesIds;

  const TaxonomyWorkPlanItem({
    required this.workKey,
    required this.runtimeEntityKey,
    required this.rank,
    required this.scientificName,
    required this.speciesIds,
  });
}
