enum HabitatTag {
  estuary,
  stream,
  lake,
  mangrove,
  reef,
  seagrass;

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
    }
  }
}
