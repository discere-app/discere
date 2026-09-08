import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/util/region_data/continent_by_country.dart';
import 'package:discere/catalog/util/region_key.dart';

/// Which continent a raw region key sits on, for grouping the region filter.
///
/// A territory code that is not itself in the table falls back to the
/// mainland country it hangs off — the Galápagos are in South America
/// because Ecuador is.
Continent? continentForCountryCode(String rawLabel) {
  final key = RegionKey.parse(rawLabel);
  if (key == null) return null;
  return continentByCountryCode[key.paddedCountryCode] ??
      continentByCountryCode[key.mainlandCountryCode];
}
