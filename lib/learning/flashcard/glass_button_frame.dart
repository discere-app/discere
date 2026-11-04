import 'package:flutter/material.dart';

/// The round, dark, translucent backdrop of the flashcard's buttons that sit
/// over an image, so they stay readable on any photo.
class GlassButtonFrame extends StatelessWidget {
  final Widget child;

  const GlassButtonFrame({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}
