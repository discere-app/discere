enum SpeciesStatus {
  active('active'),
  deprecated('deprecated');

  const SpeciesStatus(this.dbValue);

  final String dbValue;

  static SpeciesStatus fromRaw(String? rawValue) {
    return values.firstWhere(
      (status) => status.dbValue == rawValue,
      orElse: () => SpeciesStatus.active,
    );
  }
}
