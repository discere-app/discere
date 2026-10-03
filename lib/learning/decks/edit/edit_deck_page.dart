import 'dart:async';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_download_choice_dialog.dart';
import 'package:discere/learning/decks/deck_form_fields.dart';
import 'package:discere/learning/decks/edit/add_species_sheet.dart';
import 'package:discere/learning/decks/edit/edit_deck_presenter.dart';
import 'package:discere/learning/decks/edit/edit_deck_species_list.dart';
import 'package:discere/learning/decks/edit/edit_deck_tutorial.dart';
import 'package:discere/learning/decks/edit/inat_enrichment_offer.dart';
import 'package:discere/learning/decks/edit/learning_settings_section.dart';
import 'package:discere/learning/decks/edit/manual_inat_enrichment_section.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/retryable_error_state.dart';
import 'package:discere/shared/util/logger.dart';
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

/// Saving needs [_DeckLoadState.loaded]: the species list is what
/// [DecksService.updateDeck] diffs the deck's cards against, so a save
/// without it would delete every card the deck has.
enum _DeckLoadState { loading, loaded, failed }

class _EditDeckPageState extends State<EditDeckPage> {
  static const EditDeckPresenter _presenter = EditDeckPresenter();
  static final _log = Logger.forType(_EditDeckPageState);
  late final DecksService _decksService;
  late final ImageService _imageService;
  late final FlashcardService _flashcardService;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  _DeckLoadState _loadState = _DeckLoadState.loading;

  /// Set only while [_loadState] is [_DeckLoadState.failed].
  Object? _loadError;

  late List<Species> _species;
  final Set<String> _newlyAddedSpeciesIds = {};
  bool _isSaving = false;
  bool _isDirty = false;

  final GlobalKey _learningSettingsKey = GlobalKey();

  String? _coverImagePath;
  late Language _selectedLanguage;

  // Deck learning config
  late DeckConfig _deckConfig;
  late double _desiredRetention;
  late LearningMode _learningMode;
  late NameType _nameType;
  late ReviewMode _reviewMode;

  /// Snapshot of the last persisted state, compared against the live fields
  /// to drive the Save button. Taken once the deck has loaded, replaced
  /// wholesale on save.
  late EditDeckDraft _saved;

  int _distinctNameCount = 0;

  /// Applies one change to the draft the user is editing.
  ///
  /// Every such change needs the same three steps: mutate, re-validate the
  /// review mode against what the deck now contains, and re-evaluate whether
  /// anything differs from what is saved. Forgetting a step leaves the save
  /// button inactive or a review mode the deck cannot support — neither of
  /// which looks wrong on screen.
  void _applyDraftChange(VoidCallback mutate) {
    setState(() {
      mutate();
      _enforceReviewModeValidity();
      _updateDirtyState(setStateIfChanged: false);
    });
  }

  /// Recomputes [_distinctNameCount] and reverts to flip mode if multiple
  /// choice is selected but the deck no longer has enough distinct names —
  /// after a draft change, or right after loading a saved combination that
  /// is already invalid. Call within the same setState as the change.
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
    _nameController.addListener(_updateDirtyState);
    _descriptionController.addListener(_updateDirtyState);
    unawaited(_load());
  }

  /// Loads the species and the learning config, and takes them over in one
  /// step only once both are in: nothing from a failed attempt is left
  /// behind for a retry, and the review mode is validated against the
  /// complete deck. The config is a single row of the user DB, so loading
  /// it after the species rather than alongside costs nothing noticeable.
  Future<void> _load() async {
    try {
      final species = await _decksService.getSpeciesByDeckId(widget.deck.id!);
      final config = await _flashcardService.getDeckConfig(widget.deck.id!);
      if (!mounted) return;
      setState(() {
        _species = species;
        _deckConfig = config;
        _desiredRetention = config.desiredRetention;
        _learningMode = config.learningMode;
        _nameType = config.nameType;
        _reviewMode = config.reviewMode;
        // Taken before validating, so a saved combination that is no longer
        // valid shows up as an unsaved change.
        _saved = _currentDraft();
        _enforceReviewModeValidity();
        _updateDirtyState(setStateIfChanged: false);
        _loadState = _DeckLoadState.loaded;
      });
    } catch (e) {
      _log.error('Loading deck ${widget.deck.id} failed: $e');
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loadState = _DeckLoadState.failed;
      });
      return;
    }
    // Outside the try: the tutorial is not part of loading, so a failure
    // scheduling it must not take the loaded deck off the screen again.
    _maybeScheduleTutorial();
  }

  void _retryLoad() {
    setState(() {
      _loadError = null;
      _loadState = _DeckLoadState.loading;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateDirtyState);
    _descriptionController.removeListener(_updateDirtyState);
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _loadState == _DeckLoadState.loaded && _isDirty && !_isSaving;

  Future<void> _save() async {
    if (!_canSave) return;
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
    // Checked here, not only through what the UI offers: both the save
    // button and the enrichment trigger save through this method (see
    // [_DeckLoadState] for what an unloaded save would do).
    if (_loadState != _DeckLoadState.loaded) {
      throw StateError('Saving deck ${widget.deck.id} before it has loaded');
    }
    final updated = BaseDeck(
      id: widget.deck.id,
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      coverImagePath: _coverImagePath,
      language: _selectedLanguage,
    );
    await _decksService.updateDeck(updated, _species.map((s) => s.id).toSet());
    await _flashcardService.saveDeckConfig(
      _deckConfig.copyWith(
        desiredRetention: _desiredRetention,
        learningMode: _learningMode,
        nameType: _nameType,
        reviewMode: _reviewMode,
      ),
    );
    _saved = _currentDraft();
    _updateDirtyState(setStateIfChanged: false);
  }

  Future<void> _triggerINatEnrichment() async {
    if (_species.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await _saveCurrentDeck();
      if (!mounted) return;

      final enrichmentQueue = Provider.of<INatEnrichmentQueueService>(
        context,
        listen: false,
      );
      // Always re-offer the base/full/none choice rather than assuming
      // "full" — covers the never-downloaded deck (no base/cover work at
      // all yet), the base-only deck adding iNat for the first time, and a
      // fully-enriched deck the user just wants to double-check.
      await _chooseAndScheduleDownload(enrichmentQueue);
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

  Future<void> _chooseAndScheduleDownload(
    INatEnrichmentQueueService enrichmentQueue,
  ) async {
    // Don't show the button's busy spinner while waiting on the user's
    // choice in the dialog — that's an indefinite wait for input, not work
    // in progress.
    setState(() => _isSaving = false);
    final choice = await showDeckDownloadChoiceDialog(context);
    if (!mounted || choice == DeckDownloadChoice.none) return;
    setState(() => _isSaving = true);
    if (choice != DeckDownloadChoice.none) {
      // Force a genuine re-verification against the local image cache, not
      // just an idempotent no-op for species whose base capability is
      // already terminal — see retriggerBaseEnrichment's doc comment.
      await enrichmentQueue.retriggerBaseEnrichment(widget.deck.id!);
      if (!mounted) return;
    }
    await applyDeckDownloadChoice(
      context,
      enrichmentQueue,
      widget.deck.id!,
      choice,
    );
  }

  Future<void> _refreshStaleBaseImages() async {
    setState(() => _isSaving = true);
    try {
      await Provider.of<INatEnrichmentQueueService>(
        context,
        listen: false,
      ).refreshStaleBaseImages(widget.deck.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.loc.editDeckRefreshStaleImagesStarted),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmAndDeleteDeck() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.deleteDeckConfirmationTitle),
        content: Text(context.loc.deleteDeckConfirmationMessage),
        actions: [
          TextButton(
            key: const Key('edit_deck_delete_cancel_button'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.loc.commonCancel),
          ),
          TextButton(
            key: const Key('edit_deck_delete_confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.loc.deleteDeckConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    await _decksService.deleteDeck(widget.deck.id!);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _removeSpecies(Species s) {
    _applyDraftChange(() {
      _species.remove(s);
      _newlyAddedSpeciesIds.remove(s.id);
    });
  }

  Future<void> _openAddSpeciesSheet() async {
    final Species? result = await showAddSpeciesSheet(
      context,
      language: _selectedLanguage,
      alreadyAdded: _species.map((s) => s.id).toSet(),
    );
    if (result != null && mounted) {
      _applyDraftChange(() {
        _species.add(result);
        _newlyAddedSpeciesIds.add(result.id);
      });
    }
  }

  Future<void> _handleImageSelected(String? path) async {
    if (path == null) {
      if (mounted) {
        _applyDraftChange(() => _coverImagePath = null);
      }
      return;
    }

    try {
      final savedPath = await _imageService.saveCoverImage(path);
      if (mounted) {
        _applyDraftChange(() => _coverImagePath = savedPath);
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
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenEditDeckTutorial) return;
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
                onPressed: _canSave ? _save : null,
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
          child: switch (_loadState) {
            _DeckLoadState.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            _DeckLoadState.failed => RetryableErrorState(
              icon: Icons.error_outline,
              message: context.loc.editDeckLoadError(
                context.loc.describeError(_loadError),
              ),
              onRetry: _retryLoad,
              retryButtonKey: const Key('edit_deck_retry_button'),
            ),
            _DeckLoadState.loaded => _buildContent(theme),
          },
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
              DeckNameField(
                key: const Key('edit_deck_name_field'),
                controller: _nameController,
              ),
              const SizedBox(height: AppSpacing.s20),
              DeckDescriptionField(
                key: const Key('edit_deck_description_field'),
                controller: _descriptionController,
              ),
              AppSpacing.heightS24,
              DeckCoverImageField(
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
                onLanguageChanged: (newValue) =>
                    _applyDraftChange(() => _selectedLanguage = newValue),
                onRetentionChanged: (v) =>
                    _applyDraftChange(() => _desiredRetention = v),
                onLearningModeChanged: (mode) =>
                    _applyDraftChange(() => _learningMode = mode),
                onNameTypeChanged: (type) =>
                    _applyDraftChange(() => _nameType = type),
                onReviewModeChanged: (mode) =>
                    _applyDraftChange(() => _reviewMode = mode),
              ),
              AppSpacing.heightS24,
              ManualINatEnrichmentSection(
                deckId: widget.deck.id!,
                speciesCount: _species.length,
                isSaving: _isSaving,
                onTrigger: _triggerINatEnrichment,
                onRefreshStaleBaseImages: _refreshStaleBaseImages,
              ),
              AppSpacing.heightS24,
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('edit_deck_delete_button'),
                  onPressed: _isSaving ? null : _confirmAndDeleteDeck,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(context.loc.editDeckDeleteButton),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
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
        EditDeckSpeciesList(
          species: _species,
          language: _selectedLanguage,
          onOpen: _openSpeciesDetail,
          onRemove: _removeSpecies,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}
