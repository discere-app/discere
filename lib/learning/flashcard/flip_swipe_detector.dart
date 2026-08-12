import 'package:flutter/material.dart';

/// Bundles the callbacks [FlipSwipeDetector] needs to drive a live,
/// finger-following flip into one object — so [FlashcardFront] only has to
/// thread a single parameter through its several tap/drag regions instead
/// of four separate callbacks. See [FlashcardWidgetState] for how these
/// actually drive the rotation.
class FlashcardFlipController {
  final VoidCallback onTap;
  final ValueChanged<Axis> onDragStart;
  final void Function(Axis axis, double delta) onDragUpdate;
  final VoidCallback onDragEnd;

  const FlashcardFlipController({
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });
}

/// Wraps [child] so a tap flips the card, and dragging rotates it live
/// under the finger — [FlashcardWidgetState] decides on release whether
/// that drag went far enough to complete the flip or springs back.
/// Shared between [FlashcardWidget] (the back) and [FlashcardFront]
/// (everything but the image — the image already owns drags for its own
/// photo carousel and fullscreen-view gesture).
class FlipSwipeDetector extends StatefulWidget {
  final Widget child;
  final FlashcardFlipController controller;

  /// Off for the scrollable back content, where a vertical drag needs to
  /// scroll the classification list instead of flipping the card — that
  /// case uses Flutter's horizontal-only drag recognizer instead of a
  /// general pan, so it doesn't compete with the ScrollView's own vertical
  /// gestures (the same pattern used for e.g. a PageView nested inside a
  /// vertically scrolling list).
  final bool allowVertical;

  const FlipSwipeDetector({
    required this.child,
    required this.controller,
    this.allowVertical = true,
    super.key,
  });

  @override
  State<FlipSwipeDetector> createState() => _FlipSwipeDetectorState();
}

class _FlipSwipeDetectorState extends State<FlipSwipeDetector> {
  /// How much initial movement (in either direction) a vertical-allowed
  /// region waits for before committing to horizontal or vertical — avoids
  /// locking onto the wrong axis from a slightly diagonal swipe's very
  /// first pixel.
  static const double _axisLockThreshold = 12;

  Axis? _lockedAxis;
  Offset _accumulated = Offset.zero;

  @override
  Widget build(BuildContext context) {
    if (!widget.allowVertical) {
      return GestureDetector(
        onTap: widget.controller.onTap,
        onHorizontalDragStart: (_) =>
            widget.controller.onDragStart(Axis.horizontal),
        onHorizontalDragUpdate: (details) =>
            widget.controller.onDragUpdate(Axis.horizontal, details.delta.dx),
        onHorizontalDragEnd: (_) => widget.controller.onDragEnd(),
        child: widget.child,
      );
    }

    return GestureDetector(
      onTap: widget.controller.onTap,
      onPanStart: (_) {
        _lockedAxis = null;
        _accumulated = Offset.zero;
      },
      onPanUpdate: _handlePanUpdate,
      onPanEnd: (_) {
        if (_lockedAxis != null) widget.controller.onDragEnd();
        _lockedAxis = null;
      },
      child: widget.child,
    );
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    _accumulated += details.delta;
    final lockedAxis = _lockedAxis;
    if (lockedAxis == null) {
      if (_accumulated.dx.abs() < _axisLockThreshold &&
          _accumulated.dy.abs() < _axisLockThreshold) {
        return;
      }
      final axis = _accumulated.dx.abs() >= _accumulated.dy.abs()
          ? Axis.horizontal
          : Axis.vertical;
      _lockedAxis = axis;
      widget.controller.onDragStart(axis);
      // The movement spent deciding the axis counts toward the drag too,
      // so it isn't silently dropped once the axis is locked in.
      widget.controller.onDragUpdate(
        axis,
        axis == Axis.horizontal ? _accumulated.dx : _accumulated.dy,
      );
      return;
    }
    widget.controller.onDragUpdate(
      lockedAxis,
      lockedAxis == Axis.horizontal ? details.delta.dx : details.delta.dy,
    );
  }
}
