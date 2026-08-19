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

/// How long a full (1.0 turns / 180°) settle animation takes — a tap-
/// triggered flip always covers this whole distance; a drag-release settle
/// is scaled down from it in proportion to however much is actually left
/// to travel (see [FlashcardWidgetState._animateTurnsTo]), so completing a
/// drag from near the midpoint doesn't feel sluggish.
const Duration _fullSettleDuration = Duration(milliseconds: 500);
const int _minSettleDurationMs = 120;

/// Fraction of the card's own width/height a drag needs to cover before
/// releasing completes the flip instead of springing back.
const double _dragCommitThreshold = 0.3;

class FlashcardWidget extends StatefulWidget {
  final SpeciesWithLocalImages speciesWithLocalImage;
  final Language language;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;
  final List<MultipleChoiceOption> multipleChoiceOptions;

  /// Forwarded to [FlashcardBackContent] — see its doc for what this means.
  final bool namesMayStillRefine;

  /// Grades the tapped answer. The Continue button awaits this future before
  /// advancing, so the card can never advance before grading is persisted.
  final Future<void> Function(bool isCorrect)? onMultipleChoiceAnswered;
  final VoidCallback? onContinue;
  final Future<void> Function(String speciesId)? onRemoveSpecies;
  final GlobalKey? watchlistKey;
  final GlobalKey? imageKey;
  final GlobalKey? optionsKey;

  /// Called once the card's own [FlashcardFlipController] exists (in
  /// [State.initState]) — lets an ancestor (DeckPage) drive the same flip
  /// from a region it owns itself, e.g. the grading-button rail, which
  /// isn't part of this widget. See [FlashcardWidgetState.flipController].
  final ValueChanged<FlashcardFlipController>? onFlipControllerReady;

  const FlashcardWidget({
    required this.speciesWithLocalImage,
    required this.language,
    this.learningMode = LearningMode.species,
    this.nameType = NameType.commonName,
    this.reviewMode = ReviewMode.flip,
    this.multipleChoiceOptions = const [],
    this.namesMayStillRefine = false,
    this.onMultipleChoiceAnswered,
    this.onContinue,
    this.onRemoveSpecies,
    this.watchlistKey,
    this.imageKey,
    this.optionsKey,
    this.onFlipControllerReady,
    super.key,
  });

  @override
  FlashcardWidgetState createState() => FlashcardWidgetState();
}

class FlashcardWidgetState extends State<FlashcardWidget>
    with SingleTickerProviderStateMixin {
  /// Current rotation, in half-turns (1.0 == 180°, one full flip) —
  /// continuous rather than an integer so it can track a drag 1:1 under the
  /// finger in real time, not just jump between settled front/back states.
  double _turns = 0;
  Axis _flipAxis = Axis.horizontal;
  late final AnimationController _settleController;
  Animation<double>? _settleAnimation;

  /// Non-null for the duration of an active drag — the [_turns] value it
  /// started at. Drag distance is measured relative to this, and it's also
  /// what decides which content is showing (see [build]): content stays
  /// whatever it was when the drag began until the drag ends and a settle
  /// animation actually crosses the midpoint, rather than swapping mid-
  /// gesture, which would tear down and rebuild the front/back subtree the
  /// active drag's own gesture detector lives in.
  double? _dragStartTurns;

  /// Total pixel movement along the locked axis since the drag began — the
  /// gesture reports per-frame deltas, not a running total, so this has to
  /// accumulate them itself.
  double _dragAccumulatedPixels = 0;
  BoxConstraints? _constraints;

  MultipleChoiceOption? _selectedOption;
  Timer? _revealTimer;

  /// The pending grading call for the current answer, if any. The Continue
  /// button awaits this before advancing, so a slow grading write can never
  /// be raced by the user tapping Continue.
  Future<void>? _gradingFuture;

  bool get _isMultipleChoice => widget.reviewMode == ReviewMode.multipleChoice;

  FlashcardFlipController get flipController => FlashcardFlipController(
    onTap: _flip,
    onDragStart: _handleDragStart,
    onDragUpdate: _handleDragUpdate,
    onDragEnd: _handleDragEnd,
  );

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: _fullSettleDuration,
    )..addListener(_onSettleTick);
    widget.onFlipControllerReady?.call(flipController);
  }

  void _onSettleTick() {
    final animation = _settleAnimation;
    if (animation == null) return;
    setState(() => _turns = animation.value);
  }

  void _animateTurnsTo(double target) {
    final remaining = (target - _turns).abs();
    final durationMs = (remaining * _fullSettleDuration.inMilliseconds).clamp(
      _minSettleDurationMs,
      _fullSettleDuration.inMilliseconds,
    );
    _settleController.duration = Duration(milliseconds: durationMs.round());
    _settleAnimation = Tween<double>(begin: _turns, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: Curves.easeOut),
    );
    _settleController.forward(from: 0);
  }

  void _flip() => _animateTurnsTo(_turns + 1);

  void _handleDragStart(Axis axis) {
    _settleController.stop();
    setState(() {
      _flipAxis = axis;
      _dragStartTurns = _turns;
      _dragAccumulatedPixels = 0;
    });
  }

  void _handleDragUpdate(Axis axis, double axisDelta) {
    final start = _dragStartTurns;
    final constraints = _constraints;
    if (start == null || constraints == null) return;
    final extent = axis == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    if (extent <= 0) return;
    _dragAccumulatedPixels += axisDelta;
    setState(() {
      _turns = start + _dragAccumulatedPixels / extent;
    });
  }

  void _handleDragEnd() {
    final start = _dragStartTurns;
    if (start == null) return;
    _dragStartTurns = null;
    final dragged = _turns - start;
    final target = dragged.abs() >= _dragCommitThreshold
        ? start + (dragged.isNegative ? -1 : 1)
        : start;
    _animateTurnsTo(target);
  }

  void _handleOptionSelected(MultipleChoiceOption option) {
    if (_selectedOption != null) return;
    setState(() {
      _selectedOption = option;
    });
    _gradingFuture = widget.onMultipleChoiceAnswered?.call(option.isCorrect);
    _revealTimer = Timer(_multipleChoiceRevealDelay, () {
      if (mounted) _animateTurnsTo(_turns + 1);
    });
  }

  Future<void> _handleContinuePressed() async {
    await _gradingFuture;
    if (mounted) widget.onContinue?.call();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _settleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _constraints = constraints;
        final angle = _turns * math.pi;
        // Perspective, so the rotation direction is actually visible (a
        // purely orthographic rotateY/rotateX looks identical whichever
        // way it turns) — needed for the drag/swipe direction to visibly
        // match the way the card turns.
        final transform = Matrix4.identity()..setEntry(3, 2, 0.001);
        if (_flipAxis == Axis.horizontal) {
          transform.rotateY(angle);
        } else {
          transform.rotateX(angle);
        }
        // While actively dragging, keep showing whatever content the drag
        // started on (see [_dragStartTurns]'s doc) instead of swapping
        // in/out based on the live angle — that's only safe once the drag
        // has ended and a settle animation is driving [_turns] instead.
        final showingBack = _dragStartTurns != null
            ? _dragStartTurns!.round().isOdd
            : math.cos(angle) < 0;
        final isFullBleedFront = !showingBack && !_isMultipleChoice;
        final card = Transform(
          alignment: Alignment.center,
          transform: transform,
          child: Container(
            margin: isFullBleedFront
                ? EdgeInsets.zero
                : AppSpacing.paddingS20All,
            width: constraints.maxWidth,
            decoration: isFullBleedFront
                ? BoxDecoration(color: theme.cardTheme.color ?? theme.cardColor)
                : BoxDecoration(
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
              borderRadius: isFullBleedFront
                  ? BorderRadius.zero
                  : BorderRadius.circular(15),
              child: showingBack ? _buildBack() : _buildFront(),
            ),
          ),
        );

        // Both front (FlashcardFront) and back (FlashcardBackContent) wire
        // up their own tap/drag-to-flip internally now, rather than being
        // wrapped wholesale here — each needs to carve out its own
        // exceptions (front: the image, which is its own tap/drag target;
        // back: the names-may-refine info badge, which must win over the
        // ambient flip gesture on tap). MC mode never flips via gesture at
        // all, so its front/back both simply ignore flipController.
        return card;
      },
    );
  }

  Widget _buildFront() {
    if (_isMultipleChoice) {
      return FlashcardMultipleChoiceFront(
        speciesWithLocalImages: widget.speciesWithLocalImage,
        watchlistKey: widget.watchlistKey,
        imageKey: widget.imageKey,
        optionsKey: widget.optionsKey,
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
      flipController: flipController,
    );
  }

  Widget _buildBack() {
    return FlashcardBackContent(
      speciesWithLocalImages: widget.speciesWithLocalImage,
      language: widget.language,
      learningMode: widget.learningMode,
      nameType: widget.nameType,
      namesMayStillRefine: widget.namesMayStillRefine,
      // MC mode never flips via gesture, so its back gets no flip
      // controller at all — same as the pre-existing skip for MC in the
      // old external-wrap condition this replaces.
      flipController: _isMultipleChoice ? null : flipController,
      footer: _isMultipleChoice ? _buildContinueButton() : null,
      // The back's own counter-rotation (undoing the mirroring from
      // whichever axis got it here) must match the axis actually used —
      // it's always horizontal for MC (never reached via a drag, since MC
      // doesn't flip via gesture at all).
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
      _settleController.stop();
      _dragStartTurns = null;
      setState(() {
        _turns = 0;
        _flipAxis = Axis.horizontal;
        _selectedOption = null;
      });
    }
  }
}
