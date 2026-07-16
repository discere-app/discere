import 'package:flutter/material.dart';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/ocean_theme/ocean_colors.dart';
import 'import_online_deck_list_tile.dart';

class ImportOnlineDecksTab extends StatefulWidget {
  final Future<List<CreateDeck>> Function() loadDecks;
  final Future<void> Function(List<CreateDeck> selectedDecks) onImportDecks;

  const ImportOnlineDecksTab({
    required this.loadDecks,
    required this.onImportDecks,
    super.key,
  });

  @override
  State<ImportOnlineDecksTab> createState() => _ImportOnlineDecksTabState();
}

class _ImportOnlineDecksTabState extends State<ImportOnlineDecksTab> {
  // Enrichment runs through a single serialized iNat pipeline (~1 request/s),
  // so the actual slowdown scales with how many species need fresh work, not
  // how many decks that spans — warn once the combined, deduplicated species
  // count across the selection crosses this rough threshold.
  static const _manySpeciesWarningThreshold = 60;

  late Future<List<CreateDeck>> _decksFuture;
  final Set<String> _selectedDeckNames = {};
  final Set<String> _expandedDeckNames = {};
  final Map<String, Language> _languageOverridesByDeckName = {};
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _decksFuture = widget.loadDecks();
  }

  Future<void> _retry() async {
    setState(() {
      _decksFuture = widget.loadDecks();
    });
  }

  Future<void> _importSelected(List<CreateDeck> allDecks) async {
    final defaultLanguage = context.read<LanguageService>().getLanguage();
    final selectedDecks = allDecks
        .where((deck) => _selectedDeckNames.contains(deck.name))
        .map(
          (deck) => _applyLanguageOverride(
            deck,
            _languageOverridesByDeckName[deck.name] ?? defaultLanguage,
          ),
        )
        .toList();
    if (selectedDecks.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      await widget.onImportDecks(selectedDecks);
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _toggleSelection(String deckName, bool? isSelected) {
    setState(() {
      if (isSelected == true) {
        _selectedDeckNames.add(deckName);
        _languageOverridesByDeckName.putIfAbsent(
          deckName,
          () => context.read<LanguageService>().getLanguage(),
        );
      } else {
        _selectedDeckNames.remove(deckName);
        _languageOverridesByDeckName.remove(deckName);
      }
    });
  }

  int _selectedSpeciesCount(List<CreateDeck> allDecks) {
    final speciesNames = <String>{};
    for (final deck in allDecks) {
      if (!_selectedDeckNames.contains(deck.name)) continue;
      speciesNames.addAll(deck.speciesNames ?? const <String>{});
    }
    return speciesNames.length;
  }

  void _toggleExpanded(String deckName) {
    setState(() {
      if (_expandedDeckNames.contains(deckName)) {
        _expandedDeckNames.remove(deckName);
      } else {
        _expandedDeckNames.add(deckName);
      }
    });
  }

  CreateDeck _applyLanguageOverride(CreateDeck deck, Language override) {
    final clone = CreateDeck(
      id: deck.id,
      name: deck.name,
      description: deck.description,
      language: override,
      speciesNames: deck.speciesNames == null
          ? null
          : Set<String>.from(deck.speciesNames!),
      speciesIds: deck.speciesIds == null
          ? null
          : Set<String>.from(deck.speciesIds!),
      imageUrl: deck.imageUrl,
    );
    clone.coverImagePath = deck.coverImagePath;
    return clone;
  }

  @override
  Widget build(BuildContext context) {
    final defaultLanguage = context.watch<LanguageService>().getLanguage();

    return FutureBuilder<List<CreateDeck>>(
      future: _decksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          final errorMessage = error is AppException
              ? error.message
              : context.loc.importOnlineError(error.toString());
          return _ImportOnlineErrorState(
            errorMessage: errorMessage,
            onRetry: _retry,
          );
        }

        final decks = snapshot.data ?? [];
        if (decks.isEmpty) {
          return Padding(
            padding: AppSpacing.emptyStatePaddingAll,
            child: Center(
              child: Text(
                context.loc.importOnlineEmpty,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return SafeArea(
          bottom: true,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: decks.length,
                  itemBuilder: (context, index) {
                    final deck = decks[index];
                    return ImportOnlineDeckListTile(
                      deck: deck,
                      isSelected: _selectedDeckNames.contains(deck.name),
                      isExpanded: _expandedDeckNames.contains(deck.name),
                      selectedLanguage: _selectedDeckNames.contains(deck.name)
                          ? (_languageOverridesByDeckName[deck.name] ??
                                defaultLanguage)
                          : deck.language,
                      onSelected: (value) => _toggleSelection(deck.name, value),
                      onLanguageChanged: (value) {
                        setState(() {
                          _languageOverridesByDeckName[deck.name] = value;
                        });
                      },
                      onToggleExpanded: () => _toggleExpanded(deck.name),
                    );
                  },
                ),
              ),
              Padding(
                padding: AppSpacing.screenPaddingAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectedDeckNames.length > 1 &&
                        _selectedSpeciesCount(decks) >
                            _manySpeciesWarningThreshold) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s12,
                          vertical: AppSpacing.s10,
                        ),
                        decoration: BoxDecoration(
                          color: OceanColors.primaryBlue.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: OceanColors.primaryBlue.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: OceanColors.primaryBlue,
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            Expanded(
                              child: Text(
                                context.loc.importOnlineManySpeciesHint(
                                  _selectedSpeciesCount(decks),
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.heightS8,
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const ValueKey('import-online-button'),
                        onPressed: _isImporting || _selectedDeckNames.isEmpty
                            ? null
                            : () => _importSelected(decks),
                        icon: _isImporting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download),
                        label: Text(
                          context.loc.importSelectedButton(
                            _selectedDeckNames.length,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ImportOnlineErrorState extends StatelessWidget {
  final String errorMessage;
  final Future<void> Function() onRetry;

  const _ImportOnlineErrorState({
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: AppSpacing.emptyStatePaddingAll,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: AppSpacing.emptyStateIconSize,
              color: theme.colorScheme.error.withValues(alpha: 0.7),
            ),
            AppSpacing.heightS24,
            Text(
              context.loc.error,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            AppSpacing.heightS12,
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            AppSpacing.heightS32,
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                key: const ValueKey('import-retry-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.loc.commonRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
