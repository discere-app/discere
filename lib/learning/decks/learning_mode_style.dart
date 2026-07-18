import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:flutter/material.dart';

/// Icon/label/description text for [LearningMode] and [NameType], shared
/// between deck_card.dart's badge and edit_deck_page.dart's settings
/// section so both present the same enum values identically instead of
/// each maintaining its own switch.
class LearningModeStyle {
  const LearningModeStyle();

  IconData iconFor(LearningMode mode) => switch (mode) {
    LearningMode.family => Icons.account_tree_outlined,
    LearningMode.genus => Icons.category_outlined,
    LearningMode.species => Icons.badge_outlined,
  };

  String labelFor(LearningMode mode, AppLocalizations loc) => switch (mode) {
    LearningMode.family => loc.settingsLearningModeFamily,
    LearningMode.genus => loc.settingsLearningModeGenus,
    LearningMode.species => loc.settingsLearningModeSpecies,
  };

  String descriptionFor(LearningMode mode, AppLocalizations loc) =>
      switch (mode) {
        LearningMode.family => loc.settingsLearningModeDescriptionFamily,
        LearningMode.genus => loc.settingsLearningModeDescriptionGenus,
        LearningMode.species => loc.settingsLearningModeDescriptionSpecies,
      };

  IconData nameTypeIconFor(NameType type) => switch (type) {
    NameType.commonName => Icons.translate_outlined,
    NameType.scientificName => Icons.science_outlined,
  };

  String nameTypeLabelFor(NameType type, AppLocalizations loc) =>
      switch (type) {
        NameType.commonName => loc.settingsNameTypeCommonName,
        NameType.scientificName => loc.settingsNameTypeScientificName,
      };

  String nameTypeDescriptionFor(NameType type, AppLocalizations loc) =>
      switch (type) {
        NameType.commonName => loc.settingsNameTypeDescriptionCommonName,
        NameType.scientificName =>
          loc.settingsNameTypeDescriptionScientificName,
      };
}
