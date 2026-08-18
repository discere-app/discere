import 'dart:async';

import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_form_fields.dart';
import 'package:discere/learning/decks/edit/add_species_sheet.dart';
import 'package:discere/learning/decks/edit/edit_deck_presenter.dart';
import 'package:discere/learning/decks/edit/edit_deck_tutorial.dart';
import 'package:discere/learning/decks/edit/inat_enrichment_offer.dart';
import 'package:discere/learning/decks/edit/learning_settings_section.dart';
import 'package:discere/learning/decks/edit/manual_inat_enrichment_section.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

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
  static const EditDeckPresenter _presenter = EditDeckPresenter();
  late final DecksService _decksService;
  late final ImageService _imageService;
  late final FlashcardService _flashcardService;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  late Future<List<Species>> _speciesFuture;
  List<Species> _species = [];
  final Set<String> _newlyAddedSpeciesIds = {};
  bool _isSaving = false;
  bool _isDirty = false;

  final GlobalKey _learningSettingsKey = GlobalKey();
  bool _hasScheduledTutorial = false;

  String? _coverImagePath;
  late Language _selectedLanguage;

  // Deck learning config
  DeckConfig? _deckConfig;
  double _desiredRetention = 0.9;
  LearningMode _learningMode = LearningMode.species;
  NameType _nameType = NameType.commonName;
  ReviewMode _reviewMode = ReviewMode.flip;

  /// Snapshot of the last persisted state, compared against the live fields
  /// to drive the Save button. Replaced wholesale on save; updated via
  /// copyWith as the async loaders (species, deck config) come in.
  late EditDeckDraft _saved;

  int _distinctNameCount = 0;

  /// Recomputes the distinct-name count and reverts to flip mode if multiple
  /// choice is currently selected but no longer has enough distinct names
  /// (e.g. species removed, learning mode or language changed, or the
  /// initial species/config loads finished with an already-invalid saved
  /// combination). Call after any mutation to species/language/learning
  /// mode — and once after the initial async loads both complete (see
  /// [initState]) — always within the same setState.
  void _enforceReviewModeValidity() {
    _distinctNameCount = _presenter.distinctNameCount(
      _species,
      _selectedLanguage,
      _learningMode,
      _nameType,
    );
    _reviewMode = _presenter.effectiveReviewMode(
      reviewMode: _reviewMode,
      distinctNameCount: _distinctNameCount,
    );
  }

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
    _saved = EditDeckDraft(
      name: widget.deck.name,
      description: widget.deck.description,
      coverImagePath: widget.deck.coverImagePath,
      language: widget.deck.language,
      desiredRetention: _desiredRetention,
      learningMode: _learningMode,
      nameType: _nameType,
      reviewMode: _reviewMode,
      speciesIds: const {},
    );
    _nameController.addListener(_updateDirtyState);
    _descriptionController.addListener(_updateDirtyState);
    _speciesFuture = _loadSpecies();
    final configFuture = _loadDeckConfig();
    // Both loaders update their own fields independently as soon as they
    // resolve (for responsiveness), but reviewMode validity depends on BOTH
    // being complete — validating in either loader alone risks judging a
    // saved multipleChoice config against a still-empty species list (or
    // vice versa). Validate once here, after both are done.
    unawaited(
      Future.wait<Object?>([_speciesFuture, configFuture]).then((_) {
        if (mounted) {
          setState(() {
            _enforceReviewModeValidity();
            _updateDirtyState(setStateIfChanged: false);
          });
        }
      }),
    );
  }

  Future<void> _loadDeckConfig() async {
    final config = await _flashcardService.getDeckConfig(widget.deck.id!);
    if (mounted) {
      setState(() {
        _deckConfig = config;
        _desiredRetention = config.desiredRetention;
        _learningMode = config.learningMode;
        _nameType = config.nameType;
        _reviewMode = config.reviewMode;
        _saved = _saved.copyWith(
          desiredRetention: config.desiredRetention,
          learningMode: config.learningMode,
          nameType: config.nameType,
          reviewMode: config.reviewMode,
        );
      });
    }
  }

  Future<List<Species>> _loadSpecies() async {
    final list = await _decksService.getSpeciesByDeckId(widget.deck.id!);
    if (mounted) {
      setState(() {
        _species = list;
        _saved = _saved.copyWith(speciesIds: _speciesIdsFor(list));
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
      if (mounted && _newlyAddedSpeciesIds.isNotEmpty) {
        await _offerINatEnrichmentForNewSpecies();
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Mirrors the enrichment prompt shown right after creating a deck: newly
  /// added species always get their bundled reference image, and the user is
  /// asked whether to also fetch iNaturalist photos and common names for them.
  Future<void> _offerINatEnrichmentForNewSpecies() async {
    await offerINatEnrichmentForNewSpecies(context, widget.deck.id!);
    _newlyAddedSpeciesIds.clear();
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
        _deckConfig!.copyWith(
          desiredRetention: _desiredRetention,
          learningMode: _learningMode,
          nameType: _nameType,
          reviewMode: _reviewMode,
        ),
      );
    }
    _saved = _currentDraft();
    _updateDirtyState(setStateIfChanged: false);
  }

  Future<void> _triggerINatEnrichment() async {
    if (_species.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await _saveCurrentDeck();
      if (!mounted) return;

      await ensureNotificationPermission(context);
      if (!mounted) return;

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
              context.loc.editDeckINatEnrichmentError(
                context.loc.describeError(e),
              ),
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
      _newlyAddedSpeciesIds.remove(s.id);
      _enforceReviewModeValidity();
      _updateDirtyState(setStateIfChanged: false);
    });
  }

  Future<void> _openAddSpeciesSheet() async {
    final Species? result = await showAddSpeciesSheet(
      context,
      language: _selectedLanguage,
      alreadyAdded: _species.map((s) => s.id).toSet(),
    );
    if (result != null && mounted) {
      setState(() {
        _species.add(result);
        _newlyAddedSpeciesIds.add(result.id);
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
          SnackBar(
            content: Text(
              context.loc.errorSaveImage(context.loc.describeError(e)),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handlePopInvoked(bool didPop, bool? result) async {
    if (didPop) return;
    await _confirmAndPopIfNeeded();
  }

  /// Shared by the AppBar back button and [_handlePopInvoked]: a plain
  /// `Navigator.pop()` isn't gated by [PopScope]'s `canPop` — only the
  /// system back gesture is — so the button has to run the same
  /// discard-confirmation check explicitly.
  Future<void> _confirmAndPopIfNeeded() async {
    if (_isDirty) {
      final shouldDiscard = await _confirmDiscardChanges();
      if (!mounted || !shouldDiscard) return;
    }
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscardChanges() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.editDeckDiscardTitle),
        content: Text(context.loc.editDeckDiscardMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.loc.editDeckDiscardConfirm),
          ),
        ],
      ),
    );
    return shouldDiscard ?? false;
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

  EditDeckDraft _currentDraft() => EditDeckDraft(
    name: _nameController.text,
    description: _descriptionController.text,
    coverImagePath: _coverImagePath,
    language: _selectedLanguage,
    desiredRetention: _desiredRetention,
    learningMode: _learningMode,
    nameType: _nameType,
    reviewMode: _reviewMode,
    speciesIds: _speciesIdsFor(_species),
  );

  void _updateDirtyState({bool setStateIfChanged = true}) {
    final next = _presenter.isDirty(_currentDraft(), _saved);
    if (next == _isDirty) return;
    if (setStateIfChanged && mounted) {
      setState(() => _isDirty = next);
    } else {
      _isDirty = next;
    }
  }

  /// Scrolls the learning settings section into view before showing its
  /// coach mark — it sits below the name/description/cover/language
  /// sections in the scroll view, so on smaller screens it isn't visible
  /// without scrolling first.
  void _maybeScheduleTutorial() {
    if (_hasScheduledTutorial) return;
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenEditDeckTutorial) return;
    _hasScheduledTutorial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final targetContext = _learningSettingsKey.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0.1,
        );
      }
      if (!mounted) return;
      prefs.hasSeenEditDeckTutorial = true;
      EditDeckTutorial(learningSettingsKey: _learningSettingsKey).show(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmAndPopIfNeeded,
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
        body: SafeArea(
          child: FutureBuilder<List<Species>>(
            future: _speciesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _species.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              _maybeScheduleTutorial();
              return _buildContent(theme);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return CustomScrollView(
      // The default cache extent (250px) is too small to lay out the
      // learning settings section on first build if it sits below the
      // fold — _maybeScheduleTutorial needs its GlobalKey's RenderBox to
      // exist (for Scrollable.ensureVisible and the coach mark itself)
      // even before the user has scrolled there.
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
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
              DeckNameSection(
                key: const Key('edit_deck_name_field'),
                controller: _nameController,
              ),
              const SizedBox(height: AppSpacing.s20),
              DeckDescriptionSection(
                key: const Key('edit_deck_description_field'),
                controller: _descriptionController,
              ),
              AppSpacing.heightS24,
              DeckCoverImageSection(
                currentImagePath: _coverImagePath,
                onImageSelected: _handleImageSelected,
              ),
              AppSpacing.heightS24,
              LearningSettingsSection(
                titleKey: _learningSettingsKey,
                language: _selectedLanguage,
                desiredRetention: _desiredRetention,
                learningMode: _learningMode,
                nameType: _nameType,
                reviewMode: _reviewMode,
                distinctNameCount: _distinctNameCount,
                onLanguageChanged: (newValue) {
                  setState(() {
                    _selectedLanguage = newValue;
                    _enforceReviewModeValidity();
                    _updateDirtyState(setStateIfChanged: false);
                  });
                },
                onRetentionChanged: (v) {
                  setState(() {
                    _desiredRetention = v;
                    _updateDirtyState(setStateIfChanged: false);
                  });
                },
                onLearningModeChanged: (mode) {
                  setState(() {
                    _learningMode = mode;
                    _enforceReviewModeValidity();
                    _updateDirtyState(setStateIfChanged: false);
                  });
                },
                onNameTypeChanged: (type) {
                  setState(() {
                    _nameType = type;
                    _enforceReviewModeValidity();
                    _updateDirtyState(setStateIfChanged: false);
                  });
                },
                onReviewModeChanged: (mode) {
                  setState(() {
                    _reviewMode = mode;
                    _updateDirtyState(setStateIfChanged: false);
                  });
                },
              ),
              AppSpacing.heightS24,
              ManualINatEnrichmentSection(
                deckId: widget.deck.id!,
                speciesCount: _species.length,
                isSaving: _isSaving,
                onTrigger: _triggerINatEnrichment,
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
