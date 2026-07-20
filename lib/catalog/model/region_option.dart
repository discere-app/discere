import 'package:discere/catalog/model/continent.dart';

/// A selectable region (country) in the region filter/picker, resolved from
/// a raw `taxonomy_distribution_regions.region_key` country code.
class RegionOption {
  final String regionKey;
  final String label;
  final Continent? continent;

  const RegionOption({
    required this.regionKey,
    required this.label,
    this.continent,
  });
}
