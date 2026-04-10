import 'package:flutter/material.dart';

import '../../model/biology/species_with_local_images.dart';
import '../../model/language.dart';
import '../../presentation/species/flashcard_species_presenter.dart';
import '../../theme/app_spacing.dart';
import 'species_common_names_widget.dart';
import 'species_scientific_classification_widget.dart';

class FlashCardBack extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final Language language;
  static const FlashcardSpeciesPresenter _presenter =
      FlashcardSpeciesPresenter();

  const FlashCardBack({
    required this.speciesWithLocalImages,
    required this.language,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewData = _presenter.present(
      speciesWithLocalImages.species,
      language,
    );
    final identity = viewData.identity;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(3.14),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s20,
          AppSpacing.s24,
          AppSpacing.s20,
          AppSpacing.s20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildCommonNameTitle(identity.primaryName, theme),
            AppSpacing.heightS8,
            buildScientifNameSubtitle(identity.scientificName, theme),
            const SizedBox(height: AppSpacing.s20),
            SpeciesCommonNamesSection(commonNames: identity.commonNames),
            AppSpacing.heightS12,
            SpeciesScientificClassificationSection(
              rows: viewData.classificationRows,
            ),
          ],
        ),
      ),
    );
  }

  Text buildScientifNameSubtitle(String scientificName, ThemeData theme) {
    return Text(
      scientificName,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Text buildCommonNameTitle(String primaryName, ThemeData theme) {
    return Text(
      primaryName,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
