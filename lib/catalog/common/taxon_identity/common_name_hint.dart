import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Inline tap-to-explain info icon for a primary name shown next to it,
/// e.g. as a title suffix — unlike `FlashcardBackContent`'s corner badge,
/// this has no tap-to-flip gesture to avoid racing with, so it can sit
/// directly next to the text it explains. Callers decide when to show it
/// (usually `if (identity.isEnglishFallback) ...`); it renders
/// unconditionally once built.
class CommonNameHintIcon extends StatelessWidget {
  final bool namesMayStillRefine;
  final bool isEnglishFallback;
  final double size;

  const CommonNameHintIcon({
    super.key,
    this.namesMayStillRefine = false,
    required this.isEnglishFallback,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s8, top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showCommonNameHintDialog(
          context,
          namesMayStillRefine: namesMayStillRefine,
          isEnglishFallback: isEnglishFallback,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.info_outline,
            size: size,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Opens the tap-to-explain dialog for a common-name hint icon, shown next
/// to a primary name that isn't guaranteed final: [namesMayStillRefine]
/// when this species' common-name enrichment hasn't reached a terminal
/// state yet (the name may still be replaced), and [isEnglishFallback]
/// when no name exists in the requested language and an English one is
/// shown instead. Both can apply at once, in which case both paragraphs
/// are shown.
void showCommonNameHintDialog(
  BuildContext context, {
  required bool namesMayStillRefine,
  required bool isEnglishFallback,
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final loc = dialogContext.loc;
      return AlertDialog(
        title: Text(loc.commonNameHintTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (namesMayStillRefine) Text(loc.commonNameHintRefiningText),
            if (namesMayStillRefine && isEnglishFallback)
              const SizedBox(height: AppSpacing.s12),
            if (isEnglishFallback) Text(loc.commonNameHintEnglishFallbackText),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(loc.commonOk),
          ),
        ],
      );
    },
  );
}
