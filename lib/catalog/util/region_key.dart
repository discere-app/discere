/// A raw `taxonomy_distribution_regions.region_key` value, taken apart.
///
/// The format is FishBase's: a country code, optionally followed by `:` and a
/// subdivision code (`840:US-WA`). The country part is either a numeric
/// country code, which may need zero-padding to three digits, or a territory
/// code that starts with one (`218A` for the Galápagos, off `218` Ecuador).
///
/// Both things done with a region key — naming it and placing it on a
/// continent — need the same decomposition, and each used to do it for
/// itself. Doing it once means the two cannot disagree about what a key
/// means, only about what to do with it.
class RegionKey {
  /// The trimmed input, returned as-is by callers that cannot resolve it.
  final String raw;

  /// The country part exactly as written — the key territory names use,
  /// since those are not numeric and must not be padded.
  final String countryCode;

  /// [countryCode] zero-padded to three digits, the key the numeric country
  /// and continent tables use.
  final String paddedCountryCode;

  /// The part after `:`, or null when the key names a whole country.
  final String? subdivisionCode;

  const RegionKey._({
    required this.raw,
    required this.countryCode,
    required this.paddedCountryCode,
    required this.subdivisionCode,
  });

  /// Null for a blank key — there is nothing to resolve, and every caller
  /// treats that as "no region" rather than as an unknown one.
  static RegionKey? parse(String rawLabel) {
    final normalized = rawLabel.trim();
    if (normalized.isEmpty) return null;

    final parts = normalized.split(':');
    final countryCode = parts.first;
    return RegionKey._(
      raw: normalized,
      countryCode: countryCode,
      paddedCountryCode: countryCode.padLeft(3, '0'),
      subdivisionCode: parts.length > 1 ? parts.sublist(1).join(':') : null,
    );
  }

  static final _leadingDigits = RegExp(r'^(\d+)');

  /// The mainland country code a territory code hangs off — `218` for
  /// `218A`. Null when the country part does not start with digits, which is
  /// how FishBase-internal codes like `F111` are recognised.
  ///
  /// This is what makes an uncurated territory resolvable at all: it is not
  /// in any table, but the country it belongs to is.
  String? get mainlandCountryCode {
    final prefix = _leadingDigits.firstMatch(countryCode)?.group(1);
    return prefix?.padLeft(3, '0');
  }
}
