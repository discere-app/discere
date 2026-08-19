import 'dart:math' as math;

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class FlashcardBackContent extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final Language language;
  final LearningMode learningMode;
  final NameType nameType;

  /// Whether this species' common-name enrichment hasn't reached a terminal
  /// state yet, so the primary name shown above may still be replaced by a
  /// later enrichment pass — the caller (`DeckPage`) decides this per
  /// species/session; this widget only renders the resulting hint icon.
  final bool namesMayStillRefine;

  /// Optional footer (e.g. a "Continue" button) pinned below the scrollable
  /// content, inside the same counter-rotation as the rest of this widget —
  /// callers must NOT apply their own counter-rotation around a footer they
  /// render outside this widget, or it will render mirrored.
  final Widget? footer;

  /// Which axis the flip that revealed this content rotated around — the
  /// counter-rotation below must undo the SAME axis, or the content renders
  /// mirrored/upside-down instead of upright (see [FlashcardWidgetState]).
  final Axis flipAxis;

  static const FlashcardSpeciesPresenter _presenter =
      FlashcardSpeciesPresenter();

  const FlashcardBackContent({
    required this.speciesWithLocalImages,
    required this.language,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.namesMayStillRefine = false,
    this.footer,
    this.flipAxis = Axis.horizontal,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewData = _presenter.present(
      speciesWithLocalImages.species,
      language,
      learningMode: learningMode,
      nameType: nameType,
    );
    final identity = viewData.identity;

    return Transform(
      alignment: Alignment.center,
      transform: flipAxis == Axis.horizontal
          ? (Matrix4.identity()..rotateY(math.pi))
          : (Matrix4.identity()..rotateX(math.pi)),
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
                  buildCommonNameTitle(
                    context,
                    identity.primaryName,
                    theme,
                    showRefineHint: namesMayStillRefine,
                  ),
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

  Widget buildCommonNameTitle(
    BuildContext context,
    String primaryName,
    ThemeData theme, {
    required bool showRefineHint,
  }) {
    final title = CopyableText(
      text: primaryName,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      copiedStyle: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
    if (!showRefineHint) return title;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: title),
        const SizedBox(width: AppSpacing.s4),
        Padding(
          // Nudges the icon down to the title's text baseline instead of
          // its top edge, since the title can wrap to more than one line.
          padding: const EdgeInsets.only(top: AppSpacing.s4),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showRefineHint(context),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showRefineHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.loc.flashcardNameMayRefineHint)),
    );
  }
}
