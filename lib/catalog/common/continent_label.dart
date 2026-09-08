import 'package:discere/catalog/model/continent.dart';
import 'package:discere/l10n/app_localizations.dart';

/// The localized name of a continent.
///
/// One mapping rather than one per screen: the species detail page and the
/// region filter both name continents, and two copies of the same eight cases
/// would drift the moment a case is added.
///
/// A null [continent] is a region the catalog could not place on one — it
/// still has to appear in a picker, under a heading that says so.
String continentLabel(AppLocalizations loc, Continent? continent) =>
    switch (continent) {
      Continent.africa => loc.speciesDetailContinentAfrica,
      Continent.antarctica => loc.speciesDetailContinentAntarctica,
      Continent.asia => loc.speciesDetailContinentAsia,
      Continent.europe => loc.speciesDetailContinentEurope,
      Continent.northAmerica => loc.speciesDetailContinentNorthAmerica,
      Continent.oceania => loc.speciesDetailContinentOceania,
      Continent.southAmerica => loc.speciesDetailContinentSouthAmerica,
      null => loc.regionPickerOtherContinent,
    };
