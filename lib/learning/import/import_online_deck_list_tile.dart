import 'package:cached_network_image/cached_network_image.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

import '../../../../theme/app_spacing.dart';

class ImportOnlineDeckListTile extends StatelessWidget {
  final CreateDeck deck;
  final bool isSelected;
  final bool isExpanded;
  final Language selectedLanguage;
  final ValueChanged<bool?> onSelected;
  final ValueChanged<Language> onLanguageChanged;
  final VoidCallback onToggleExpanded;

  const ImportOnlineDeckListTile({
    required this.deck,
    required this.isSelected,
    required this.isExpanded,
    required this.selectedLanguage,
    required this.onSelected,
    required this.onLanguageChanged,
    required this.onToggleExpanded,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescription = deck.description.trim().isNotEmpty;
    final speciesCountLabel = context.loc.importOnlineSpeciesCount(
      deck.speciesNames?.length ?? 0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      child: Material(
        color: isSelected
            ? OceanColors.primaryBlue.withValues(alpha: 0.08)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('deck-checkbox-${deck.name}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelected(!isSelected),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.s10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? OceanColors.primaryBlue.withValues(alpha: 0.35)
                    : OceanColors.elementDarkborder,
                width: isSelected ? 1.25 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DeckPreviewImage(imageUrl: deck.imageUrl),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      if (hasDescription)
                        _ExpandableDescription(
                          text: deck.description,
                          speciesCountLabel: speciesCountLabel,
                          isExpanded: isExpanded,
                        )
                      else
                        Text(
                          speciesCountLabel,
                          style: theme.textTheme.labelSmall,
                        ),
                      if (isSelected) ...[
                        const SizedBox(height: AppSpacing.s4),
                        const SizedBox(height: AppSpacing.s10),
                        Text(
                          context.loc.createDeckLanguageLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        DropdownButtonFormField<Language>(
                          key: ValueKey('import-online-language-${deck.name}'),
                          isExpanded: true,
                          initialValue: selectedLanguage,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: Language.values.map((language) {
                            return DropdownMenuItem<Language>(
                              value: language,
                              child: Text(
                                context.loc.commonLanguages(language.name),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          selectedItemBuilder: (context) {
                            return Language.values
                                .map(
                                  (language) => Text(
                                    context.loc.commonLanguages(language.name),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                )
                                .toList();
                          },
                          onChanged: (value) {
                            if (value != null) {
                              onLanguageChanged(value);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s4),
                      child: Checkbox(value: isSelected, onChanged: onSelected),
                    ),
                    if (hasDescription)
                      IconButton(
                        onPressed: onToggleExpanded,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: AppSpacing.s24,
                          minHeight: AppSpacing.s24,
                        ),
                        iconSize: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                        icon: AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(Icons.expand_more),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckPreviewImage extends StatelessWidget {
  final String? imageUrl;

  const _DeckPreviewImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    const size = 52.0;

    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: const Icon(Icons.image_not_supported),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[300]),
        errorWidget: (context, url, error) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }
}

class _ExpandableDescription extends StatelessWidget {
  final String text;
  final String speciesCountLabel;
  final bool isExpanded;

  const _ExpandableDescription({
    required this.text,
    required this.speciesCountLabel,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isExpanded) {
      return Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(speciesCountLabel, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
