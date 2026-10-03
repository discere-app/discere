import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Says why a card of a multiple-choice deck is asked by flipping: there were
/// too few answer options for it (see `DeckSessionPresenter.isFlipFallback`).
/// A quiet note in the style of [TapToRevealHint] rather than a warning — the
/// card is fully learnable this way, the user only needs to know it is meant
/// to look different.
class FlipFallbackNotice extends StatelessWidget {
  /// Icon above text instead of beside it — used in the narrow landscape
  /// hints column, mirroring [HintRow.stacked].
  final bool stacked;

  const FlipFallbackNotice({this.stacked = false, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.55);
    final icon = Icon(Icons.info_outline, size: 16, color: color);
    final text = Text(
      context.loc.flashcardFlipFallbackNotice,
      style: theme.textTheme.labelMedium?.copyWith(color: color),
    );

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [icon, AppSpacing.heightS4, text],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        AppSpacing.widthS8,
        Flexible(child: text),
      ],
    );
  }
}
