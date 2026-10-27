import 'package:discere/learning/import/import_online_deck_presenter.dart';
import 'package:discere/learning/import/widgets/deck_learning_settings_chips.dart';
import 'package:discere/learning/import/widgets/deck_preview_image.dart';
import 'package:discere/learning/import/widgets/expandable_description.dart';
import 'package:discere/learning/import/widgets/status_label.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/ocean_theme/ocean_colors.dart';
import 'package:flutter/material.dart';

class ImportOnlineDeckListTile extends StatelessWidget {
  final CreateDeck deck;
  final ImportOnlineDeckStatus status;
  final bool isSelected;
  final bool isExpanded;
  final Language selectedLanguage;
  final ValueChanged<bool?> onSelected;
  final ValueChanged<Language> onLanguageChanged;
  final VoidCallback onToggleExpanded;

  /// The local decks this entry supersedes, for
  /// [ImportOnlineDeckStatus.supersedesLocal].
  final List<String> supersededDeckNames;

  /// What the status offers instead of a selection — the deck update, or
  /// the merge of the decks this entry supersedes.
  final VoidCallback? onStatusAction;

  const ImportOnlineDeckListTile({
    required this.deck,
    required this.status,
    required this.isSelected,
    required this.isExpanded,
    required this.selectedLanguage,
    required this.onSelected,
    required this.onLanguageChanged,
    required this.onToggleExpanded,
    this.supersededDeckNames = const [],
    this.onStatusAction,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescription = deck.description.trim().isNotEmpty;
    final speciesCountLabel = context.loc.importOnlineSpeciesCount(
      deck.speciesNames?.length ?? 0,
    );
    final tint = isSelected
        ? OceanColors.primaryBlue
        : switch (status) {
            ImportOnlineDeckStatus.updateAvailable => OceanColors.success,
            ImportOnlineDeckStatus.supersedesLocal => OceanColors.primaryBlue,
            _ => null,
          };
    final onTap = switch (status) {
      ImportOnlineDeckStatus.notImported => () => onSelected(!isSelected),
      ImportOnlineDeckStatus.updateAvailable ||
      ImportOnlineDeckStatus.supersedesLocal => onStatusAction,
      ImportOnlineDeckStatus.upToDate => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s4,
      ),
      child: TappableSectionCard(
        key: ValueKey('deck-checkbox-${deck.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        tint: tint,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DeckPreviewImage(imageUrl: deck.imageUrl),
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
                      ExpandableDescription(
                        text: deck.description,
                        speciesCountLabel: speciesCountLabel,
                        isExpanded: isExpanded,
                      )
                    else
                      Text(
                        speciesCountLabel,
                        style: theme.textTheme.labelSmall,
                      ),
                    // Only an entry still to be imported starts from the
                    // catalog's settings: an update keeps the user's deck
                    // config, and a merge takes over the superseded deck's.
                    if (status == ImportOnlineDeckStatus.notImported) ...[
                      const SizedBox(height: AppSpacing.s8),
                      DeckLearningSettingsChips(
                        learningMode:
                            deck.learningMode ?? DeckConfig.defaultLearningMode,
                        nameType: deck.nameType ?? DeckConfig.defaultNameType,
                        reviewMode:
                            deck.reviewMode ?? DeckConfig.defaultReviewMode,
                      ),
                    ] else ...[
                      const SizedBox(height: AppSpacing.s4),
                      StatusLabel(
                        status: status,
                        supersededDeckNames: supersededDeckNames,
                      ),
                    ],
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
                    child: switch (status) {
                      ImportOnlineDeckStatus.notImported => Checkbox(
                        value: isSelected,
                        onChanged: onSelected,
                      ),
                      ImportOnlineDeckStatus.upToDate => Tooltip(
                        message: context.loc.importOnlineAlreadyImported,
                        child: Icon(
                          Icons.check_circle_outline,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      ImportOnlineDeckStatus.updateAvailable => IconButton(
                        key: ValueKey('import-online-update-${deck.name}'),
                        onPressed: onStatusAction,
                        tooltip: context.loc.importOnlineUpdateAvailable,
                        icon: Icon(
                          Icons.system_update_alt,
                          color: OceanColors.success,
                        ),
                      ),
                      ImportOnlineDeckStatus.supersedesLocal => IconButton(
                        key: ValueKey('import-online-merge-${deck.name}'),
                        onPressed: onStatusAction,
                        tooltip: context.loc.deckMergeDialogTitle,
                        icon: Icon(
                          Icons.merge_type,
                          color: OceanColors.primaryBlue,
                        ),
                      ),
                    },
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
    );
  }
}
