import 'dart:async';

import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/presentation/enrichment_status_presenter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import '../../theme/app_spacing.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/import/inat_download_dialog.dart';
import 'package:discere/shared/ui/image_picker.dart';

class EditDeckPage extends StatefulWidget {
  final BaseDeck deck;
  final Widget Function(String speciesId, Language? language)
  buildSpeciesDetailPage;

  const EditDeckPage({
    required this.deck,
    required this.buildSpeciesDetailPage,
    super.key,
  });

  @override
  State<EditDeckPage> createState() => _EditDeckPageState();
}

class _EditDeckPageState extends State<EditDeckPage> {
  static const SpeciesListItemPresenter _speciesListItemPresenter =
      SpeciesListItemPresenter();
  late final DecksService _decksService;
  late final ImageService _imageService;
  late final FlashcardService _flashcardService;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  late Future<List<Species>> _speciesFuture;
  List<Species> _species = [];
  bool _isSaving = false;
  bool _isDirty = false;

  String? _coverImagePath;
  late Language _selectedLanguage;
  late String _savedName;
  late String _savedDescription;
  String? _savedCoverImagePath;
  late Language _savedLanguage;
  Set<String> _savedSpeciesIds = {};

  // Deck learning config
  DeckConfig? _deckConfig;
  double _desiredRetention = 0.9;

  @override
  void initState() {
    super.initState();
    _decksService = Provider.of<DecksService>(context, listen: false);
    _imageService = Provider.of<ImageService>(context, listen: false);
    _flashcardService = Provider.of<FlashcardService>(context, listen: false);
    _nameController = TextEditingController(text: widget.deck.name);
    _descriptionController = TextEditingController(
      text: widget.deck.description,
    );
    _coverImagePath = widget.deck.coverImagePath;
    _selectedLanguage = widget.deck.language;
    _savedName = widget.deck.name.trim();
    _savedDescription = widget.deck.description.trim();
    _savedCoverImagePath = widget.deck.coverImagePath;
    _savedLanguage = widget.deck.language;
    _nameController.addListener(_updateDirtyState);
    _descriptionController.addListener(_updateDirtyState);
    _speciesFuture = _loadSpecies();
    _loadDeckConfig();
  }

  Future<void> _loadDeckConfig() async {
    final config = await _flashcardService.getDeckConfig(widget.deck.id!);
    if (mounted) {
      setState(() {
        _deckConfig = config;
        _desiredRetention = config.desiredRetention;
      });
    }
  }

  Future<List<Species>> _loadSpecies() async {
    final list = await _decksService.getSpeciesByDeckId(widget.deck.id!);
    if (mounted) {
      setState(() {
        _species = list;
        _savedSpeciesIds = _speciesIdsFor(list);
        _updateDirtyState(setStateIfChanged: false);
      });
    }
    return list;
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateDirtyState);
    _descriptionController.removeListener(_updateDirtyState);
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_isDirty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _saveCurrentDeck();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveCurrentDeck() async {
    final updated = BaseDeck(
      widget.deck.id,
      _nameController.text.trim(),
      _descriptionController.text.trim(),
      coverImagePath: _coverImagePath,
      language: _selectedLanguage,
    );
    await _decksService.updateDeck(updated, _species.map((s) => s.id).toSet());
    // Save deck config if loaded
    if (_deckConfig != null) {
      await _flashcardService.saveDeckConfig(
        _deckConfig!.copyWith(desiredRetention: _desiredRetention),
      );
    }
    _markCurrentStateSaved();
  }

  Future<void> _triggerINatEnrichment() async {
    if (_species.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await _saveCurrentDeck();
      if (!mounted) return;

      final notificationService = Provider.of<NotificationService>(
        context,
        listen: false,
      );
      if (await notificationService.shouldPromptForPermission() && mounted) {
        final shouldRequest = await showEnrichmentNotificationPermissionDialog(
          context,
        );
        if (!mounted) return;
        if (shouldRequest) {
          await notificationService.requestPermissions();
          if (!mounted) return;
        }
      }

      await Provider.of<INatEnrichmentQueueService>(
        context,
        listen: false,
      ).scheduleDeckEnrichment(
        [widget.deck.id!],
        includeINatPhotos: true,
        includeCommonNames: true,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.loc.editDeckINatEnrichmentError(e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _removeSpecies(Species s) {
    setState(() {
      _species.remove(s);
      _updateDirtyState(setStateIfChanged: false);
    });
  }

  Future<void> _openAddSpeciesSheet() async {
    final Species? result = await showModalBottomSheet<Species>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddSpeciesSheet(
        language: _selectedLanguage,
        alreadyAdded: _species.map((s) => s.id).toSet(),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _species.add(result);
        _updateDirtyState(setStateIfChanged: false);
      });
    }
  }

  Future<void> _handleImageSelected(String? path) async {
    if (path == null) {
      if (mounted) {
        setState(() {
          _coverImagePath = null;
          _updateDirtyState(setStateIfChanged: false);
        });
      }
      return;
    }

    try {
      final savedPath = await _imageService.saveCoverImage(path);
      if (mounted) {
        setState(() {
          _coverImagePath = savedPath;
          _updateDirtyState(setStateIfChanged: false);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.loc.errorSaveImage(e.toString()))),
        );
      }
    }
  }

  Future<void> _openSpeciesDetail(Species species) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            widget.buildSpeciesDetailPage(species.id, _selectedLanguage),
      ),
    );
  }

  Set<String> _speciesIdsFor(List<Species> species) =>
      species.map((s) => s.id).toSet();

  void _markCurrentStateSaved() {
    _savedName = _nameController.text.trim();
    _savedDescription = _descriptionController.text.trim();
    _savedCoverImagePath = _coverImagePath;
    _savedLanguage = _selectedLanguage;
    _savedSpeciesIds = _speciesIdsFor(_species);
    _updateDirtyState(setStateIfChanged: false);
  }

  bool _computeIsDirty() {
    return _nameController.text.trim() != _savedName ||
        _descriptionController.text.trim() != _savedDescription ||
        _coverImagePath != _savedCoverImagePath ||
        _selectedLanguage != _savedLanguage ||
        !_setEquals(_speciesIdsFor(_species), _savedSpeciesIds);
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  void _updateDirtyState({bool setStateIfChanged = true}) {
    final next = _computeIsDirty();
    if (next == _isDirty) return;
    if (setStateIfChanged && mounted) {
      setState(() => _isDirty = next);
    } else {
      _isDirty = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(context.loc.editDeckTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.elementSpacing),
            child: TextButton.icon(
              key: const Key('edit_deck_save_button'),
              onPressed: _isSaving || !_isDirty ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 18),
              label: Text(context.loc.editSaveButton),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Species>>(
        future: _speciesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _species.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildContent(colorScheme, theme);
        },
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme, ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
            AppSpacing.screenPadding,
            AppSpacing.elementSpacing,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                context.loc.createDeckNameLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              TextField(
                key: const Key('edit_deck_name_field'),
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.loc.createDeckNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.s20),
              Text(
                context.loc.createDescriptionLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              TextField(
                key: const Key('edit_deck_description_field'),
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.loc.createDescriptionHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              AppSpacing.heightS24,
              Text(
                context.loc.createCoverImageLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              ImagePicker(
                currentImagePath: _coverImagePath,
                getSearchQuery: () => _nameController.text.trim(),
                onImageSelected: _handleImageSelected,
              ),
              AppSpacing.heightS24,
              Text(
                context.loc.createDeckLanguageLabel,
                style: theme.textTheme.titleSmall,
              ),
              AppSpacing.heightS8,
              DropdownButtonFormField<Language>(
                initialValue: _selectedLanguage,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: Language.values.map((lang) {
                  return DropdownMenuItem<Language>(
                    value: lang,
                    child: Text(context.loc.commonLanguages(lang.name)),
                  );
                }).toList(),
                onChanged: (Language? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedLanguage = newValue;
                      _updateDirtyState(setStateIfChanged: false);
                    });
                  }
                },
              ),
              AppSpacing.heightS24,
              _ManualINatEnrichmentSection(
                deckId: widget.deck.id!,
                speciesCount: _species.length,
                isSaving: _isSaving,
                onTrigger: _triggerINatEnrichment,
              ),
              AppSpacing.heightS24,
              _LerneinstellungenSection(
                desiredRetention: _desiredRetention,
                onRetentionChanged: (v) {
                  setState(() {
                    _desiredRetention = v;
                    _isDirty = true;
                  });
                },
              ),
              AppSpacing.heightS24,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.loc.editSpeciesInDeck(_species.length),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('edit_deck_add_species_button'),
                    onPressed: _openAddSpeciesSheet,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.loc.editAddSpeciesButton),
                  ),
                ],
              ),
              AppSpacing.heightS12,
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.zero,
          sliver: SliverList.builder(
            itemCount: _species.length,
            itemBuilder: (context, index) {
              final s = _species[index];
              return SpeciesListItem(
                key: ValueKey(s.id),
                item: _speciesListItemPresenter.presentSpecies(
                  s,
                  _selectedLanguage,
                ),
                onTap: () => _openSpeciesDetail(s),
                onDelete: () => _removeSpecies(s),
                deleteTooltip: context.loc.editRemoveTooltip,
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

class _ManualINatEnrichmentSection extends StatelessWidget {
  final String deckId;
  final int speciesCount;
  final bool isSaving;
  final Future<void> Function() onTrigger;

  const _ManualINatEnrichmentSection({
    required this.deckId,
    required this.speciesCount,
    required this.isSaving,
    required this.onTrigger,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Selector<INatEnrichmentQueueService, DeckEnrichmentInfo>(
      selector: (context, service) => service.deckInfo(deckId),
      builder: (context, info, child) {
        final hasSpecies = speciesCount > 0;
        final isBusy =
            info.isActive || (info.hasPendingWork && !info.hasFailedAttempt);
        final canTrigger = hasSpecies && !isBusy && !isSaving;
        final status = _statusFor(context, info, hasSpecies);
        final buttonLabel = info.hasCompletedINatEnrichment
            ? context.loc.editDeckINatEnrichmentButtonAgain
            : context.loc.editDeckINatEnrichmentButtonNow;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.editDeckINatEnrichmentTitle,
              style: theme.textTheme.titleSmall,
            ),
            AppSpacing.heightS8,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.s16),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(status.icon, size: 20, color: status.color),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.loc.editDeckINatEnrichmentStatusLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            AppSpacing.heightS4,
                            Text(
                              status.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: status.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  AppSpacing.heightS12,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('edit_deck_inat_enrichment_button'),
                      onPressed: canTrigger ? onTrigger : null,
                      icon: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: Text(buttonLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  _ManualINatStatus _statusFor(
    BuildContext context,
    DeckEnrichmentInfo info,
    bool hasSpecies,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!hasSpecies) {
      return _ManualINatStatus(
        text: context.loc.editDeckINatEnrichmentNoSpecies,
        icon: Icons.info_outline,
        color: colorScheme.onSurfaceVariant,
      );
    }
    if (info.isActive) {
      final phaseLabel =
          _phaseLabel(context, info.currentPhase) ??
          context.loc.editDeckINatEnrichmentActive;
      return _ManualINatStatus(
        text: _statusWithProgress(context, phaseLabel, info),
        icon: Icons.cloud_sync_outlined,
        color: colorScheme.primary,
      );
    }
    if (info.hasFailedAttempt) {
      return _ManualINatStatus(
        text: context.loc.editDeckINatEnrichmentFailed,
        icon: Icons.error_outline,
        color: colorScheme.error,
      );
    }
    if (info.hasPendingWork) {
      return _ManualINatStatus(
        text: formatDeckPendingStatusLabel(
          context.loc,
          hasActiveHostCooldown: info.hasActiveHostCooldown,
          isQuickPassReady: info.isQuickPassReady,
          phase: info.currentPhase,
          fallback: context.loc.editDeckINatEnrichmentPending,
        ),
        icon: info.hasActiveHostCooldown
            ? Icons.cloud_off_outlined
            : info.isQuickPassReady
            ? Icons.check_circle_outline
            : Icons.hourglass_top_outlined,
        color: info.isQuickPassReady && !info.hasActiveHostCooldown
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      );
    }
    if (info.hasCompletedINatEnrichment) {
      return _ManualINatStatus(
        text: context.loc.editDeckINatEnrichmentLastUpdated(
          _formatDateTime(context, info.lastCompletedAt!),
        ),
        icon: Icons.check_circle_outline,
        color: colorScheme.onSurfaceVariant,
      );
    }
    return _ManualINatStatus(
      text: context.loc.editDeckINatEnrichmentNever,
      icon: Icons.info_outline,
      color: colorScheme.onSurfaceVariant,
    );
  }

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    return DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm().format(dateTime);
  }

  String _statusWithProgress(
    BuildContext context,
    String status,
    DeckEnrichmentInfo info,
  ) {
    if (info.progressTotal <= 0) return status;
    return context.loc.editDeckINatEnrichmentStatusProgress(
      status,
      info.progressCompleted,
      info.progressTotal,
    );
  }

  String? _phaseLabel(BuildContext context, INatEnrichmentPhase? phase) {
    return formatEnrichmentPhaseLabel(context.loc, phase);
  }
}

class _ManualINatStatus {
  final String text;
  final IconData icon;
  final Color color;

  const _ManualINatStatus({
    required this.text,
    required this.icon,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Learning settings section
// ─────────────────────────────────────────────────────────────────────────────

class _LerneinstellungenSection extends StatelessWidget {
  final double desiredRetention;
  final ValueChanged<double> onRetentionChanged;

  const _LerneinstellungenSection({
    required this.desiredRetention,
    required this.onRetentionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pct = (desiredRetention * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lerneinstellungen', style: theme.textTheme.titleSmall),
        AppSpacing.heightS8,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Gewünschte Retention',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '$pct %',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                key: const Key('retention_slider'),
                value: desiredRetention,
                min: 0.70,
                max: 0.97,
                divisions: 27,
                onChanged: onRetentionChanged,
              ),
              Text(
                'Höhere Werte bedeuten mehr Wiederholungen, aber besseres Behalten.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-species bottom sheet with inline search
// ─────────────────────────────────────────────────────────────────────────────

class _AddSpeciesSheet extends StatefulWidget {
  final Language language;
  final Set<String> alreadyAdded;

  const _AddSpeciesSheet({required this.language, required this.alreadyAdded});

  @override
  State<_AddSpeciesSheet> createState() => _AddSpeciesSheetState();
}

class _AddSpeciesSheetState extends State<_AddSpeciesSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _loading = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _searchController.text.trim();
    if (q == _query) return;
    _query = q;
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final repo = Provider.of<SearchRepository>(context, listen: false);
    final results = await repo.searchAll(q);
    if (!mounted) return;
    setState(() {
      _results = results
          .where((r) => r.type == SearchEntityType.species)
          .toList();
      _loading = false;
    });
  }

  Future<void> _selectResult(SearchResult result) async {
    final decksService = Provider.of<DecksService>(context, listen: false);
    final speciesList = await decksService.getSpeciesByIds({result.id});
    if (!mounted) return;
    if (speciesList.isNotEmpty) {
      Navigator.of(context).pop(speciesList.first);
    }
  }

  String _displayName(SearchResult r) {
    return resolvePrimaryCommonName(
      r.commonNames,
      widget.language,
      fallback: r.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    context.loc.editAddSpeciesButton,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.loc.editSearchSpeciesHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _results = [];
                              _query = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _buildResultsList(scrollController, colorScheme, theme),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultsList(
    ScrollController scrollController,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(
          context.loc.editTypeToSearch,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          context.loc.editNoSpeciesFound,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final alreadyIn = widget.alreadyAdded.contains(r.id);
        final name = _displayName(r);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(
            name,
            style: alreadyIn
                ? TextStyle(color: colorScheme.onSurfaceVariant)
                : null,
          ),
          subtitle: Text(
            r.name,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          trailing: alreadyIn
              ? Icon(Icons.check, color: colorScheme.primary)
              : const Icon(Icons.add),
          onTap: alreadyIn ? null : () => _selectResult(r),
        );
      },
    );
  }
}
