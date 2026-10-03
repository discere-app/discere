import 'dart:math' as math;

import 'package:discere/catalog/common/taxon_identity/common_name_hint.dart';
import 'package:discere/catalog/common/taxon_identity/display_language_selector.dart';
import 'package:discere/catalog/common/taxon_identity/display_languages.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_view_model.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/watchlist_button.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class FlashcardBackContent extends StatefulWidget {
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

  /// Drives tap/drag-to-flip for everything except the hint badge, language
  /// selector, and watchlist button, which are rendered as Stack siblings
  /// instead of nested descendants precisely so each can win the tap
  /// outright — a tap target nested inside a widget that ALSO recognizes
  /// tap-to-flip is exactly the kind of gesture-arena race FlashcardFront
  /// already avoids for its image (see its doc). Null in multiple-choice
  /// mode, which never flips via gesture.
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

  /// Same key the front's watchlist button uses — safe to share since front
  /// and back are never mounted at the same time (see [FlashcardWidget]).
  final GlobalKey? watchlistKey;

  const FlashcardBackContent({
    required this.speciesWithLocalImages,
    required this.language,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.namesMayStillRefine = false,
    this.flipController,
    this.footer,
    this.flipAxis = Axis.horizontal,
    this.watchlistKey,
    super.key,
  });

  @override
  State<FlashcardBackContent> createState() => _FlashcardBackContentState();
}

class _FlashcardBackContentState extends State<FlashcardBackContent> {
  static const FlashcardSpeciesPresenter _presenter =
      FlashcardSpeciesPresenter();

  /// The language this card's name and classification are currently shown
  /// in — starts at [FlashcardBackContent.language] (the deck's configured
  /// language) but can be switched ad hoc via the language selector chip,
  /// purely as a one-card peek. No explicit reset on card change is needed:
  /// DeckPage mounts a fresh FlashcardWidget per card via a ValueKey on the
  /// card index (see its doc), so this state is always recreated from
  /// scratch for a new card rather than updated in place.
  late Language _displayLanguage = widget.language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewData = _presenter.present(
      widget.speciesWithLocalImages.species,
      _displayLanguage,
      learningMode: widget.learningMode,
      nameType: widget.nameType,
    );
    final identity = viewData.identity;
    final showHintBadge =
        widget.namesMayStillRefine || identity.isEnglishFallback;

    final scrollableContent = SingleChildScrollView(
      // Top padding clears the floating language-selector/hint-badge row
      // (Positioned top: s12, roughly 30 tall) so the title never sits
      // underneath it — that row is unconditional now that the language
      // selector always shows, not just occasionally like the hint badge
      // alone used to.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.s32 + AppSpacing.s24,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCommonNameTitle(identity.primaryName, theme),
          AppSpacing.heightS8,
          _buildScientificNameSubtitle(identity.scientificName, theme),
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
          child: widget.flipController == null
              ? scrollableContent
              : FlipSwipeDetector(
                  controller: widget.flipController!,
                  allowVertical: false,
                  child: scrollableContent,
                ),
        ),
        ?widget.footer,
      ],
    );

    return Transform(
      alignment: Alignment.center,
      transform: widget.flipAxis == Axis.horizontal
          ? (Matrix4.identity()..rotateY(math.pi))
          : (Matrix4.identity()..rotateX(math.pi)),
      child: Stack(
        children: [
          flippableBody,
          // Same top-right spot and glass look as the front's button (see
          // FlashcardImageHeader) so it doesn't visually jump when flipping.
          Positioned(
            top: AppSpacing.s12,
            right: AppSpacing.s12,
            child: WatchlistButton(
              speciesId: widget.speciesWithLocalImages.species.id,
              buttonKey: widget.watchlistKey,
              glass: true,
            ),
          ),
          // Language selector and hint badge share one corner, in a Row —
          // the selector is always shown (it's not conditional on anything
          // about this card), the hint badge only joins it when relevant,
          // so they never fight over the same spot.
          Positioned(
            top: AppSpacing.s12,
            left: AppSpacing.s12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A Stack sibling of the flip-gesture area for the same
                // reason as the hint badge: its own tap target sits on top
                // in paint order, so a tap opens the menu instead of racing
                // the ambient flip gesture underneath.
                DisplayLanguageSelector(
                  language: _displayLanguage,
                  selectableLanguages: selectableDisplayLanguages(
                    widget.speciesWithLocalImages.species.commonNames,
                    _displayLanguage,
                  ),
                  onSelected: (language) =>
                      setState(() => _displayLanguage = language),
                ),
                if (showHintBadge) ...[
                  AppSpacing.widthS8,
                  _buildHintBadge(context, theme, identity),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScientificNameSubtitle(String scientificName, ThemeData theme) {
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

  Widget _buildCommonNameTitle(String primaryName, ThemeData theme) {
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
  // purpose — see [FlashcardBackContent.flipController]'s doc. Its own
  // Material+InkWell tap target sits on top in paint order, so hit-testing
  // resolves to it exclusively instead of racing the ambient flip gesture
  // underneath.
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
          namesMayStillRefine: widget.namesMayStillRefine,
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
