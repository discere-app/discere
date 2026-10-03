String? formatYears(double? years, String Function(int years) localizeYears) {
  if (years == null) return null;
  return localizeYears(years.round());
}
