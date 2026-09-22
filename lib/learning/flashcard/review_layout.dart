import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Arranges the card and its rating buttons for the orientation at hand.
///
/// Landscape moves the rating buttons into a vertical rail beside the card
/// instead of a row below it, so the card doesn't lose height to a
/// horizontal button strip (see [FlashcardButtons.vertical]) — a landscape
/// phone screen has very little height to begin with. It also drops the
/// interval previews: the rail has no room for them.
class ReviewLayout extends StatelessWidget {
  /// The card itself, or whatever stands in for it when the session has
  /// none.
  final Widget cardArea;

  /// Only flip mode rates a card; multiple choice advances by tapping an
  /// option.
  final bool showRatingButtons;

  /// Drives the same tap/drag-to-flip as the card itself, so the button rail
  /// flips too — in landscape the card's own swipeable area can be narrow.
  final FlashcardFlipController flipController;

  /// Interval previews under each rating button. Portrait only.
  final Map<ReviewGrade, String> previews;

  final void Function(ReviewGrade grade) onGrade;
  final GlobalKey againKey;
  final GlobalKey hardKey;
  final GlobalKey goodKey;
  final GlobalKey easyKey;

  const ReviewLayout({
    required this.cardArea,
    required this.showRatingButtons,
    required this.flipController,
    required this.previews,
    required this.onGrade,
    required this.againKey,
    required this.hardKey,
    required this.goodKey,
    required this.easyKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return isLandscape ? _buildLandscape() : _buildPortrait();
  }

  /// A bare Row doesn't stretch to fill the available height on its own —
  /// its cross axis just shrink-wraps to the tallest child — so the
  /// LayoutBuilder gives it an explicit, tight height to lay out against.
  /// Without it a Row child (the button rail) collapses to an under-sized
  /// height instead of filling the space. Column doesn't need this:
  /// MainAxisSize.max already fills a loose bound along its own main axis.
  Widget _buildLandscape() {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: Row(
          children: [
            Expanded(child: cardArea),
            if (showRatingButtons)
              SizedBox(
                width: 116,
                child: FlipSwipeDetector(
                  controller: flipController,
                  child: FlashcardButtons(
                    vertical: true,
                    onAgain: () => onGrade(ReviewGrade.again),
                    onHard: () => onGrade(ReviewGrade.hard),
                    onGood: () => onGrade(ReviewGrade.good),
                    onEasy: () => onGrade(ReviewGrade.easy),
                    againKey: againKey,
                    hardKey: hardKey,
                    goodKey: goodKey,
                    easyKey: easyKey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortrait() {
    return Column(
      children: [
        Expanded(child: cardArea),
        if (showRatingButtons) ...[
          AppSpacing.heightS24,
          FlipSwipeDetector(
            controller: flipController,
            child: FlashcardButtons(
              onAgain: () => onGrade(ReviewGrade.again),
              onHard: () => onGrade(ReviewGrade.hard),
              onGood: () => onGrade(ReviewGrade.good),
              onEasy: () => onGrade(ReviewGrade.easy),
              timeAgain: previews[ReviewGrade.again] ?? '',
              timeHard: previews[ReviewGrade.hard] ?? '',
              timeGood: previews[ReviewGrade.good] ?? '',
              timeEasy: previews[ReviewGrade.easy] ?? '',
              againKey: againKey,
              hardKey: hardKey,
              goodKey: goodKey,
              easyKey: easyKey,
            ),
          ),
        ],
      ],
    );
  }
}
