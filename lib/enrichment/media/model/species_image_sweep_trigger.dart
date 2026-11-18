/// What made the species image storage be swept.
enum SpeciesImageSweepTrigger {
  /// The species the app needs, or the installed reference database,
  /// changed since the last sweep.
  automatic('automatic'),

  /// Asked for on the diagnostics page.
  manual('manual');

  const SpeciesImageSweepTrigger(this.wireName);

  /// The value stored with a sweep's result. Spelled out rather than derived
  /// from [name], so renaming a constant cannot make a stored result
  /// unreadable.
  final String wireName;

  static SpeciesImageSweepTrigger fromWire(String wireName) =>
      values.firstWhere(
        (trigger) => trigger.wireName == wireName,
        orElse: () =>
            throw ArgumentError.value(wireName, 'wireName', 'Unknown trigger'),
      );
}
