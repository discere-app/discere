import 'dart:math' as math;

import 'package:discere/catalog/common/taxon_identity/common_name_hint.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/model/deck_config.dart';
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
  /// species/session; this widget only renders the resulting hint badge.
  /// Combined with the presenter-derived `identity.isEnglishFallback` (OR'd
  /// together) to decide whether the badge shows at all.
  final bool namesMayStillRefine;

  /// Drives tap/drag-to-flip for everything except the hint badge, which is
  /// rendered as a Stack sibling instead of a nested descendant precisely
  /// so it can win the tap outright — a tap target nested inside a widget
  /// that ALSO recognizes tap-to-flip is exactly the kind of gesture-arena
  /// race FlashcardFront already avoids for its image (see its doc). Null
  /// in multiple-choice mode, which never flips via gesture.
  final FlashcardFlipController? flipController;

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
    this.flipController,
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
    final showHintBadge = namesMayStillRefine || identity.isEnglishFallback;

    final scrollableContent = SingleChildScrollView(
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
    );

    final flippableBody = Column(
      children: [
        Expanded(
          child: flipController == null
              ? scrollableContent
              : FlipSwipeDetector(
                  controller: flipController!,
                  allowVertical: false,
                  child: scrollableContent,
                ),
        ),
        ?footer,
      ],
    );

    return Transform(
      alignment: Alignment.center,
      transform: flipAxis == Axis.horizontal
          ? (Matrix4.identity()..rotateY(math.pi))
          : (Matrix4.identity()..rotateX(math.pi)),
      child: showHintBadge
          ? Stack(
              children: [
                flippableBody,
                Positioned(
                  top: AppSpacing.s12,
                  right: AppSpacing.s12,
                  child: _buildHintBadge(context, theme, identity),
                ),
              ],
            )
          : flippableBody,
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

  // A Stack sibling (not a nested descendant) of the flip-gesture area on
  // purpose — see [flipController]'s doc. Its own Material+InkWell tap
  // target sits on top in paint order, so hit-testing resolves to it
  // exclusively instead of racing the ambient flip gesture underneath.
  Widget _buildHintBadge(
    BuildContext context,
    ThemeData theme,
    TaxonIdentityViewModel identity,
  ) {
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showCommonNameHintDialog(
          context,
          namesMayStillRefine: namesMayStillRefine,
          isEnglishFallback: identity.isEnglishFallback,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
