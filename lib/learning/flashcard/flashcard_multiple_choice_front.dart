import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/flashcard_image_header.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The front of a flashcard in multiple-choice review mode: the image plus
/// 4 name options, exactly one of which is correct.
class FlashcardMultipleChoiceFront extends StatelessWidget {
  final SpeciesWithLocalImages speciesWithLocalImages;
  final GlobalKey? watchlistKey;
  final GlobalKey? imageKey;
  final GlobalKey? optionsKey;
  final List<MultipleChoiceOption> options;
  final MultipleChoiceOption? selectedOption;
  final ValueChanged<MultipleChoiceOption> onOptionSelected;
  final Future<void> Function(String speciesId)? onRemoveSpecies;

  const FlashcardMultipleChoiceFront({
    required this.speciesWithLocalImages,
    required this.options,
    required this.onOptionSelected,
    this.watchlistKey,
    this.imageKey,
    this.optionsKey,
    this.selectedOption,
    this.onRemoveSpecies,
    super.key,
  }) : assert(
         options.length == 4,
         'FlashcardMultipleChoiceFront requires exactly 4 options, got '
         '${options.length}',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final image = FlashcardImageHeader(
      speciesWithLocalImages: speciesWithLocalImages,
      watchlistKey: watchlistKey,
      imageKey: imageKey,
      onRemoveSpecies: onRemoveSpecies,
    );

    final promptAndOptions = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s20,
        isLandscape ? AppSpacing.s20 : AppSpacing.s16,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.loc.flashcardMultipleChoicePrompt,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          AppSpacing.heightS8,
          Expanded(
            child: KeyedSubtree(
              key: optionsKey,
              child: isLandscape
                  ? _optionColumn(context, theme)
                  : Column(
                      children: [
                        Expanded(child: _optionRow(context, theme, 0, 1)),
                        AppSpacing.heightS8,
                        Expanded(child: _optionRow(context, theme, 2, 3)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );

    if (isLandscape) {
      return Row(
        children: [
          Expanded(flex: 6, child: image),
          Expanded(flex: 4, child: promptAndOptions),
        ],
      );
    }

    return Column(
      children: [
        Expanded(flex: 6, child: image),
        Expanded(flex: 4, child: promptAndOptions),
      ],
    );
  }

  /// Landscape stacks all 4 options in a single narrow column instead of the
  /// portrait 2x2 grid — the right-hand pane is narrower there, and species
  /// names can be long.
  Widget _optionColumn(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) AppSpacing.heightS8,
          Expanded(child: _optionTile(context, theme, options[i])),
        ],
      ],
    );
  }

  Widget _optionRow(
    BuildContext context,
    ThemeData theme,
    int firstIndex,
    int secondIndex,
  ) {
    return Row(
      children: [
        Expanded(child: _optionTile(context, theme, options[firstIndex])),
        AppSpacing.widthS8,
        Expanded(child: _optionTile(context, theme, options[secondIndex])),
      ],
    );
  }

  Widget _optionTile(
    BuildContext context,
    ThemeData theme,
    MultipleChoiceOption option,
  ) {
    final isAnswered = selectedOption != null;
    final isSelected = option == selectedOption;
    final isCorrect = option.isCorrect;

    Color borderColor = theme.colorScheme.onSurface.withValues(alpha: 0.15);
    Color backgroundColor = theme.colorScheme.surface.withValues(alpha: 0.5);
    Color textColor = theme.colorScheme.onSurface;
    IconData? icon;

    if (isAnswered) {
      if (isCorrect) {
        borderColor = Colors.tealAccent.shade400;
        backgroundColor = Colors.tealAccent.shade400.withValues(alpha: 0.15);
        textColor = Colors.tealAccent.shade700;
        icon = Icons.check_circle;
      } else if (isSelected) {
        borderColor = Colors.redAccent;
        backgroundColor = Colors.redAccent.withValues(alpha: 0.12);
        textColor = Colors.redAccent;
        icon = Icons.cancel;
      } else {
        textColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);
      }
    }

    return InkWell(
      onTap: isAnswered ? null : () => onOptionSelected(option),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor, size: 16),
              AppSpacing.widthS4,
            ],
            Flexible(
              child: Text(
                option.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
