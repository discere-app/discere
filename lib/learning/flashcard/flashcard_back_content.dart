import 'package:flutter/material.dart';

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import '../../theme/app_spacing.dart';

class FlashcardBackContent extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final Language language;
  final LearningMode learningMode;

  /// Optional footer (e.g. a "Continue" button) pinned below the scrollable
  /// content, inside the same counter-rotation as the rest of this widget —
  /// callers must NOT apply their own counter-rotation around a footer they
  /// render outside this widget, or it will render mirrored.
  final Widget? footer;
  static const FlashcardSpeciesPresenter _presenter =
      FlashcardSpeciesPresenter();

  const FlashcardBackContent({
    required this.speciesWithLocalImages,
    required this.language,
    this.learningMode = LearningMode.species,
    this.footer,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewData = _presenter.present(
      speciesWithLocalImages.species,
      language,
      learningMode: learningMode,
    );
    final identity = viewData.identity;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(3.14),
      child: Column(
        children: [
          Expanded(
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
          ),
          ?footer,
        ],
      ),
    );
  }

  Widget buildScientifNameSubtitle(String scientificName, ThemeData theme) {
    return CopyableText(
      text: scientificName,
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
      ),
      copiedStyle: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.primary,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget buildCommonNameTitle(String primaryName, ThemeData theme) {
    return CopyableText(
      text: primaryName,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      copiedStyle: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
