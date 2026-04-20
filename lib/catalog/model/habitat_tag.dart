enum HabitatTag {
  estuary,
  stream,
  lake,
  mangrove,
  reef,
  seagrass,
  freshwater,
  lagoon,
  cave,
  openOcean,
  openOceanEpipelagic,
  openOceanMesopelagic,
  hardBottom,
  softBottom,
  demersal,
  bathydemersal,
  pelagic,
  epipelagic,
  bathypelagic,
  benthic,
  benthopelagic,
  littoral,
  neritic,
  pelagicNeritic,
  pelagicOceanic;

  static HabitatTag? fromTraitKey(String traitKey) {
    switch (traitKey.trim().toLowerCase()) {
      case 'estuary_association':
      case 'estuaries_association':
        return HabitatTag.estuary;
      case 'freshwater_stream_association':
      case 'stream_association':
        return HabitatTag.stream;
      case 'lake_association':
      case 'lakes_association':
        return HabitatTag.lake;
      case 'mangrove_association':
      case 'mangroves_association':
        return HabitatTag.mangrove;
      case 'reef_association':
      case 'coral_reef_association':
        return HabitatTag.reef;
      case 'seagrass_association':
      case 'sea_grass_association':
        return HabitatTag.seagrass;
    }

    return null;
  }

  static HabitatTag? fromRawHabitat(String rawHabitat) {
    switch (rawHabitat.trim().toLowerCase()) {
      case 'estuary':
      case 'estuaries':
        return HabitatTag.estuary;
      case 'freshwater stream':
      case 'stream':
        return HabitatTag.stream;
      case 'freshwater':
        return HabitatTag.freshwater;
      case 'freshwater lake':
      case 'lake':
      case 'lakes':
        return HabitatTag.lake;
      case 'mangrove':
      case 'mangroves':
        return HabitatTag.mangrove;
      case 'coral reef':
      case 'reef':
      case 'coral reefs':
        return HabitatTag.reef;
      case 'seagrass':
      case 'sea grass':
      case 'seagrass beds':
      case 'sea grass beds':
        return HabitatTag.seagrass;
      case 'lagoon':
        return HabitatTag.lagoon;
      case 'cave':
        return HabitatTag.cave;
      case 'open ocean':
        return HabitatTag.openOcean;
      case 'open ocean (epipelagic)':
        return HabitatTag.openOceanEpipelagic;
      case 'open ocean (mesopelagic)':
        return HabitatTag.openOceanMesopelagic;
      case 'hard bottom':
        return HabitatTag.hardBottom;
      case 'soft bottom':
        return HabitatTag.softBottom;
      case 'demersal':
        return HabitatTag.demersal;
      case 'bathydemersal':
        return HabitatTag.bathydemersal;
      case 'pelagic':
        return HabitatTag.pelagic;
      case 'epipelagic':
        return HabitatTag.epipelagic;
      case 'bathypelagic':
        return HabitatTag.bathypelagic;
      case 'benthic':
        return HabitatTag.benthic;
      case 'benthopelagic':
        return HabitatTag.benthopelagic;
      case 'littoral':
        return HabitatTag.littoral;
      case 'neritic':
        return HabitatTag.neritic;
      case 'pelagic-neritic':
        return HabitatTag.pelagicNeritic;
      case 'pelagic-oceanic':
        return HabitatTag.pelagicOceanic;
    }

    return null;
  }

  String get label {
    switch (this) {
      case HabitatTag.estuary:
        return 'Estuary';
      case HabitatTag.stream:
        return 'Stream';
      case HabitatTag.lake:
        return 'Lake';
      case HabitatTag.mangrove:
        return 'Mangrove';
      case HabitatTag.reef:
        return 'Coral reef';
      case HabitatTag.seagrass:
        return 'Seagrass';
      case HabitatTag.freshwater:
        return 'Freshwater';
      case HabitatTag.lagoon:
        return 'Lagoon';
      case HabitatTag.cave:
        return 'Cave';
      case HabitatTag.openOcean:
        return 'Open ocean';
      case HabitatTag.openOceanEpipelagic:
        return 'Open ocean (epipelagic)';
      case HabitatTag.openOceanMesopelagic:
        return 'Open ocean (mesopelagic)';
      case HabitatTag.hardBottom:
        return 'Hard bottom';
      case HabitatTag.softBottom:
        return 'Soft bottom';
      case HabitatTag.demersal:
        return 'Demersal';
      case HabitatTag.bathydemersal:
        return 'Bathydemersal';
      case HabitatTag.pelagic:
        return 'Pelagic';
      case HabitatTag.epipelagic:
        return 'Epipelagic';
      case HabitatTag.bathypelagic:
        return 'Bathypelagic';
      case HabitatTag.benthic:
        return 'Benthic';
      case HabitatTag.benthopelagic:
        return 'Benthopelagic';
      case HabitatTag.littoral:
        return 'Littoral';
      case HabitatTag.neritic:
        return 'Neritic';
      case HabitatTag.pelagicNeritic:
        return 'Pelagic-neritic';
      case HabitatTag.pelagicOceanic:
        return 'Pelagic-oceanic';
    }
  }
}
