import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:flutter/material.dart';

/// Icon/label/description text for [LearningMode] and [NameType], shared
/// between deck_card.dart's badge and edit_deck_page.dart's settings
/// section so both present the same enum values identically instead of
/// each maintaining its own switch.
class LearningModeStyle {
  const LearningModeStyle();

  // Reuses SearchTaxonomyStyle's per-rank icons (species/genus/family) so a
  // rank means the same icon everywhere in the app, not just here.
  IconData iconFor(LearningMode mode) => SearchTaxonomyStyle.iconFor(
    switch (mode) {
      LearningMode.family => SearchEntityType.family,
      LearningMode.genus => SearchEntityType.genus,
      LearningMode.species => SearchEntityType.species,
    },
  );

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
    NameType.commonName => Icons.chat_bubble_outline,
    NameType.scientificName => Icons.biotech_outlined,
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

  String reviewModeLabelFor(ReviewMode mode, AppLocalizations loc) =>
      switch (mode) {
        ReviewMode.flip => loc.settingsReviewModeFlip,
        ReviewMode.multipleChoice => loc.settingsReviewModeMultipleChoice,
      };

  IconData reviewModeIconFor(ReviewMode mode) => switch (mode) {
    ReviewMode.flip => Icons.flip_camera_android_outlined,
    ReviewMode.multipleChoice => Icons.checklist_outlined,
  };
}
