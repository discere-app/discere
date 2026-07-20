import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/l10n/app_localizations.dart';

/// Localized label for a [RegionAbundance] tier, or `null` for "present but
/// unrated"/"no distribution data".
String regionAbundanceLabel(AppLocalizations loc, RegionAbundance? tier) {
  switch (tier) {
    case RegionAbundance.abundant:
      return loc.regionAbundanceAbundant;
    case RegionAbundance.common:
      return loc.regionAbundanceCommon;
    case RegionAbundance.fairlyCommon:
      return loc.regionAbundanceFairlyCommon;
    case RegionAbundance.occasional:
      return loc.regionAbundanceOccasional;
    case RegionAbundance.scarce:
      return loc.regionAbundanceScarce;
    case null:
      return loc.regionAbundanceUnknown;
  }
}
