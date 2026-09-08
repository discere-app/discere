import 'package:discere/shared/model/language.dart';

/// FishBase territory codes that are not ISO country codes — islands and
/// dependencies it tracks separately from their mainland country (`218A`
/// Galápagos, `840B` Hawaii). Keyed by the raw code, not the zero-padded
/// one, because these are not numeric.
///
/// Falls back to English per code, like [countryNamesByLanguage].
const Map<Language, Map<String, String>> specialTerritoryNamesByLanguage = {
  Language.en: _en,
  Language.de: _de,
};

const Map<String, String> _en = {
  '152A': 'Easter Island',
  '152B': 'Juan Fernández Islands',
  '152D': 'Desventuradas Islands',
  '218A': 'Galápagos Islands',
  '250A': 'Society Islands',
  '250C': 'Tuamotu Islands',
  '250D': 'Marquesas Islands',
  '260A': 'Amsterdam Island',
  '392B': 'Ryukyu Islands',
  '554A': 'Kermadec Islands',
  '554C': 'Chatham Islands',
  '598A': 'Admiralty Islands',
  '620A': 'Madeira Islands',
  '620B': 'Azores',
  '724A': 'Canary Islands',
  '826A': 'England and Wales',
  '826B': 'Scotland',
  '840A': 'Alaska',
  '840B': 'Hawaii',
  'I188': 'Cocos Island',
};

const Map<String, String> _de = {
  '152A': 'Osterinsel',
  '152B': 'Juan-Fernández-Inseln',
  '152D': 'Desventuradas-Inseln',
  '218A': 'Galápagosinseln',
  '250A': 'Gesellschaftsinseln',
  '250C': 'Tuamotu-Archipel',
  '250D': 'Marquesas-Inseln',
  '260A': 'Amsterdaminsel',
  '392B': 'Ryūkyū-Inseln',
  '554A': 'Kermadecinseln',
  '554C': 'Chatham-Inseln',
  '598A': 'Admiralitätsinseln',
  '620A': 'Madeira',
  '620B': 'Azoren',
  '724A': 'Kanarische Inseln',
  '826A': 'England und Wales',
  '826B': 'Schottland',
  '840A': 'Alaska',
  '840B': 'Hawaii',
  'I188': 'Kokos-Insel',
};
