import 'package:discere/shared/model/language.dart';

enum HabitatTagEnum {
  estuary,
  stream,
  lake,
  mangrove,
  reef,
  seagrass;

  static HabitatTagEnum? fromTraitKey(String traitKey) {
    switch (traitKey.trim().toLowerCase()) {
      case 'estuary_association':
      case 'estuaries_association':
        return HabitatTagEnum.estuary;
      case 'freshwater_stream_association':
      case 'stream_association':
        return HabitatTagEnum.stream;
      case 'lake_association':
      case 'lakes_association':
        return HabitatTagEnum.lake;
      case 'mangrove_association':
      case 'mangroves_association':
        return HabitatTagEnum.mangrove;
      case 'reef_association':
      case 'coral_reef_association':
        return HabitatTagEnum.reef;
      case 'seagrass_association':
      case 'sea_grass_association':
        return HabitatTagEnum.seagrass;
    }

    return null;
  }

  static HabitatTagEnum? fromRawHabitat(String rawHabitat) {
    switch (rawHabitat.trim().toLowerCase()) {
      case 'estuary':
      case 'estuaries':
        return HabitatTagEnum.estuary;
      case 'freshwater stream':
      case 'stream':
        return HabitatTagEnum.stream;
      case 'freshwater lake':
      case 'lake':
      case 'lakes':
        return HabitatTagEnum.lake;
      case 'mangrove':
      case 'mangroves':
        return HabitatTagEnum.mangrove;
      case 'coral reef':
      case 'reef':
      case 'coral reefs':
        return HabitatTagEnum.reef;
      case 'seagrass':
      case 'sea grass':
      case 'seagrass beds':
      case 'sea grass beds':
        return HabitatTagEnum.seagrass;
    }

    return null;
  }

  String localizedLabel(Language language) {
    switch (this) {
      case HabitatTagEnum.estuary:
        return switch (language) {
          Language.de => 'Ästuar',
          Language.en => 'Estuary',
          Language.fr => 'Estuaire',
          Language.es => 'Estuario',
        };
      case HabitatTagEnum.stream:
        return switch (language) {
          Language.de => 'Fließgewässer',
          Language.en => 'Stream',
          Language.fr => 'Cours d\'eau',
          Language.es => 'Arroyo',
        };
      case HabitatTagEnum.lake:
        return switch (language) {
          Language.de => 'See',
          Language.en => 'Lake',
          Language.fr => 'Lac',
          Language.es => 'Lago',
        };
      case HabitatTagEnum.mangrove:
        return switch (language) {
          Language.de => 'Mangrove',
          Language.en => 'Mangrove',
          Language.fr => 'Mangrove',
          Language.es => 'Manglar',
        };
      case HabitatTagEnum.reef:
        return switch (language) {
          Language.de => 'Korallenriff',
          Language.en => 'Coral reef',
          Language.fr => 'Récif corallien',
          Language.es => 'Arrecife coralino',
        };
      case HabitatTagEnum.seagrass:
        return switch (language) {
          Language.de => 'Seegras',
          Language.en => 'Seagrass',
          Language.fr => 'Herbier marin',
          Language.es => 'Pastos marinos',
        };
    }
  }
}
