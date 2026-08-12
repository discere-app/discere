import 'dart:async';
import 'dart:math' as math;

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'package:discere/learning/flashcard/flashcard_front.dart';
import 'package:discere/learning/flashcard/flashcard_multiple_choice_front.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Delay between an answer tap in multiple-choice mode and automatically
/// flipping to the back content, so the user sees the correct/incorrect
/// highlight on the tapped tile before the reveal.
const Duration _multipleChoiceRevealDelay = Duration(milliseconds: 600);

class FlashcardWidget extends StatefulWidget {
  final SpeciesWithLocalImages speciesWithLocalImage;
  final Language language;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;
  final List<MultipleChoiceOption> multipleChoiceOptions;

  /// Grades the tapped answer. The Continue button awaits this future before
  /// advancing, so the card can never advance before grading is persisted.
  final Future<void> Function(bool isCorrect)? onMultipleChoiceAnswered;
  final VoidCallback? onContinue;
  final Future<void> Function(String speciesId)? onRemoveSpecies;
  final GlobalKey? watchlistKey;
  final GlobalKey? imageKey;

  const FlashcardWidget({
    required this.speciesWithLocalImage,
    required this.language,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.reviewMode = ReviewMode.flip,
    this.multipleChoiceOptions = const [],
    this.onMultipleChoiceAnswered,
    this.onContinue,
    this.onRemoveSpecies,
    this.watchlistKey,
    this.imageKey,
    super.key,
  });

  @override
  FlashcardWidgetState createState() => FlashcardWidgetState();
}

class FlashcardWidgetState extends State<FlashcardWidget> {
  /// Total half-turns applied so far (can go negative — a left/up swipe
  /// counts down, a right/down swipe counts up), driving both which face
  /// shows (odd = back) and the animated rotation's sign, so the card
  /// visually turns the way it was swiped instead of always the same way.
  int _turns = 0;
  Axis _flipAxis = Axis.horizontal;
  MultipleChoiceOption? _selectedOption;
  Timer? _revealTimer;

  /// The pending grading call for the current answer, if any. The Continue
  /// button awaits this before advancing, so a slow grading write can never
  /// be raced by the user tapping Continue.
  Future<void>? _gradingFuture;

  bool get _showData => _turns.isOdd;

  bool get _isMultipleChoice => widget.reviewMode == ReviewMode.multipleChoice;

  void _flip({FlipDirection? direction}) {
    setState(() {
      switch (direction) {
        case FlipDirection.left:
          _flipAxis = Axis.horizontal;
          _turns--;
        case FlipDirection.right:
          _flipAxis = Axis.horizontal;
          _turns++;
        case FlipDirection.up:
          _flipAxis = Axis.vertical;
          _turns--;
        case FlipDirection.down:
          _flipAxis = Axis.vertical;
          _turns++;
        case null:
          // Tap (no directional intent) keeps turning the same way it was
          // already going, on whichever axis a prior swipe last used.
          _turns++;
      }
    });
  }

  void _handleOptionSelected(MultipleChoiceOption option) {
    if (_selectedOption != null) return;
    setState(() {
      _selectedOption = option;
    });
    _gradingFuture = widget.onMultipleChoiceAnswered?.call(option.isCorrect);
    _revealTimer = Timer(_multipleChoiceRevealDelay, () {
      if (mounted) {
        setState(() {
          _turns++;
        });
      }
    });
  }

  Future<void> _handleContinuePressed() async {
    await _gradingFuture;
    if (mounted) widget.onContinue?.call();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final card = TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _turns.toDouble()),
          duration: const Duration(milliseconds: 500),
          builder: (BuildContext context, double val, _) {
            final angle = val * math.pi;
            // Perspective, so the rotation direction is actually visible
            // (a purely orthographic rotateY/rotateX looks identical
            // whichever way it turns) — needed now that swipe direction is
            // supposed to be visible in which way the card turns.
            final transform = Matrix4.identity()..setEntry(3, 2, 0.001);
            if (_flipAxis == Axis.horizontal) {
              transform.rotateY(angle);
            } else {
              transform.rotateX(angle);
            }
            // Which face is actually pointed at the viewer RIGHT NOW, given
            // the animation's current angle — not [_showData] (the
            // end-of-animation target). Using the target here would swap
            // the content the INSTANT a flip starts rather than once the
            // card has actually turned edge-on, so the back would render
            // face-on but upside down and visibly un-rotate into place
            // over the second half of the animation instead of turning in
            // already right-side up.
            final showingBack = math.cos(angle) < 0;
            final isFullBleedFront = !showingBack && !_isMultipleChoice;
            return Transform(
              alignment: Alignment.center,
              transform: transform,
              child: Container(
                margin: isFullBleedFront
                    ? EdgeInsets.zero
                    : AppSpacing.paddingS20All,
                width: constraints.maxWidth,
                decoration: isFullBleedFront
                    ? BoxDecoration(
                        color: theme.cardTheme.color ?? theme.cardColor,
                      )
                    : BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        color: theme.cardTheme.color ?? theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                child: ClipRRect(
                  borderRadius: isFullBleedFront
                      ? BorderRadius.zero
                      : BorderRadius.circular(15),
                  child: showingBack ? _buildBack() : _buildFront(),
                ),
              ),
            );
          },
        );

        // The flip-mode front handles tap/swipe-to-flip itself, on
        // everything except the image (see FlashcardFront) — the image is
        // a tap target for fullscreen instead, and a swipe there pages
        // through its own photo carousel, so neither can also flip the
        // card. MC mode never flips via gesture at all. The back has no
        // image and nothing to page through, so wrapping the whole thing
        // is safe there — except vertical swipes, which the scrollable
        // classification list needs for itself.
        if (_isMultipleChoice || !_showData) return card;
        return FlipSwipeDetector(
          onTap: _flip,
          onSwipe: (direction) => _flip(direction: direction),
          allowVertical: false,
          child: card,
        );
      },
    );
  }

  Widget _buildFront() {
    if (_isMultipleChoice) {
      return FlashcardMultipleChoiceFront(
        speciesWithLocalImages: widget.speciesWithLocalImage,
        watchlistKey: widget.watchlistKey,
        options: widget.multipleChoiceOptions,
        selectedOption: _selectedOption,
        onOptionSelected: _handleOptionSelected,
        onRemoveSpecies: widget.onRemoveSpecies,
      );
    }
    return FlashcardFront(
      speciesWithLocalImages: widget.speciesWithLocalImage,
      watchlistKey: widget.watchlistKey,
      imageKey: widget.imageKey,
      onRemoveSpecies: widget.onRemoveSpecies,
      onFlip: _flip,
    );
  }

  Widget _buildBack() {
    return FlashcardBackContent(
      speciesWithLocalImages: widget.speciesWithLocalImage,
      language: widget.language,
      learningMode: widget.learningMode,
      nameType: widget.nameType,
      footer: _isMultipleChoice ? _buildContinueButton() : null,
      // The back's own counter-rotation (undoing the mirroring from
      // whichever axis got it here) must match the axis actually used —
      // it's always horizontal for MC (never reached via a vertical swipe,
      // since MC doesn't flip via gesture at all).
      flipAxis: _isMultipleChoice ? Axis.horizontal : _flipAxis,
    );
  }

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        0,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: widget.onContinue == null ? null : _handleContinuePressed,
          style: FilledButton.styleFrom(
            padding: AppSpacing.buttonPaddingVertical,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          child: Text(context.loc.flashcardContinueButton),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant FlashcardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speciesWithLocalImage != oldWidget.speciesWithLocalImage) {
      _revealTimer?.cancel();
      _gradingFuture = null;
      setState(() {
        _turns = 0;
        _flipAxis = Axis.horizontal;
        _selectedOption = null;
      });
    }
  }
}
