import 'dart:async';

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/flashcard_back_content.dart';
import 'package:discere/learning/flashcard/flashcard_front.dart';
import 'package:discere/learning/flashcard/flashcard_multiple_choice_front.dart';
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
    this.watchlistKey,
    this.imageKey,
    super.key,
  });

  @override
  FlashcardWidgetState createState() => FlashcardWidgetState();
}

class FlashcardWidgetState extends State<FlashcardWidget> {
  bool _showData = false;
  MultipleChoiceOption? _selectedOption;
  Timer? _revealTimer;

  /// The pending grading call for the current answer, if any. The Continue
  /// button awaits this before advancing, so a slow grading write can never
  /// be raced by the user tapping Continue.
  Future<void>? _gradingFuture;

  bool get _isMultipleChoice => widget.reviewMode == ReviewMode.multipleChoice;

  void _flip() {
    setState(() {
      _showData = !_showData;
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
          _showData = true;
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
    return GestureDetector(
      onTap: _isMultipleChoice ? null : _flip,
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0, end: _showData ? 180 : 0),
        duration: const Duration(milliseconds: 500),
        builder: (BuildContext context, double val, _) {
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateY(val * (3.14 / 180)),
            child: Container(
              margin: AppSpacing.paddingS20All,
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
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
                borderRadius: BorderRadius.circular(15),
                child: _showData ? _buildBack() : _buildFront(),
              ),
            ),
          );
        },
      ),
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
      );
    }
    return FlashcardFront(
      speciesWithLocalImages: widget.speciesWithLocalImage,
      watchlistKey: widget.watchlistKey,
      imageKey: widget.imageKey,
    );
  }

  Widget _buildBack() {
    return FlashcardBackContent(
      speciesWithLocalImages: widget.speciesWithLocalImage,
      language: widget.language,
      learningMode: widget.learningMode,
      nameType: widget.nameType,
      footer: _isMultipleChoice ? _buildContinueButton() : null,
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
          onPressed: widget.onContinue == null
              ? null
              : _handleContinuePressed,
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
        _showData = false;
        _selectedOption = null;
      });
    }
  }
}
