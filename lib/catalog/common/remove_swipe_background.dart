import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// What shows behind a species card while it is swiped away to remove it from
/// a list — the watchlist's and a comparison's. The margin matches the card's,
/// so the background stays behind it.
class RemoveSwipeBackground extends StatelessWidget {
  const RemoveSwipeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.s20),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.elementSpacing,
      ),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}
