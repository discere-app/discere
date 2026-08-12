import 'package:flutter/material.dart';

/// Which way a swipe should visually rotate the flashcard — see
/// [FlashcardWidgetState] for how this maps onto the rotation axis/sign.
enum FlipDirection { left, right, up, down }

/// Wraps [child] so a tap OR a swipe past a small distance threshold flips
/// the card, with the swipe's direction passed through so the rotation can
/// match it. Shared between [FlashcardWidget] (the back) and
/// [FlashcardFront] (everything but the image — the image already owns
/// horizontal swipes for its own photo carousel).
class FlipSwipeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final ValueChanged<FlipDirection> onSwipe;

  /// Off for the scrollable back content, where a vertical drag needs to
  /// scroll the classification list instead of flipping the card.
  final bool allowVertical;

  const FlipSwipeDetector({
    required this.child,
    required this.onTap,
    required this.onSwipe,
    this.allowVertical = true,
    super.key,
  });

  @override
  State<FlipSwipeDetector> createState() => _FlipSwipeDetectorState();
}

class _FlipSwipeDetectorState extends State<FlipSwipeDetector> {
  static const double _swipeThreshold = 40;

  Offset _cumulativeDelta = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onPanStart: (_) => _cumulativeDelta = Offset.zero,
      onPanUpdate: (details) => _cumulativeDelta += details.delta,
      onPanEnd: _handlePanEnd,
      child: widget.child,
    );
  }

  void _handlePanEnd(DragEndDetails details) {
    final dx = _cumulativeDelta.dx;
    final dy = _cumulativeDelta.dy;

    if (dx.abs() >= dy.abs()) {
      if (dx.abs() < _swipeThreshold) return;
      widget.onSwipe(dx < 0 ? FlipDirection.left : FlipDirection.right);
    } else {
      if (!widget.allowVertical || dy.abs() < _swipeThreshold) return;
      widget.onSwipe(dy < 0 ? FlipDirection.up : FlipDirection.down);
    }
  }
}
